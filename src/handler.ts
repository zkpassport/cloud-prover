import { exec } from "child_process"
import { promisify } from "util"
import * as fs from "fs"
import * as os from "os"
import * as path from "path"
import { Request, Response } from "express"
import { executeCircuit, compressWitness } from "@aztec/noir-acvm_js"
import { generateWitnessMap } from "./utils"

const BB_VERSIONS = {
  "0.69.0": "bb_0.69.0",
  "0.72.1": "bb_0.72.1",
  "0.73.0": "bb_0.73.0",
  "0.74.0": "bb_0.74.0",
  "v0.82.2": "bb",
}

const execAsync = promisify(exec)
const writeFileAsync = promisify(fs.writeFile)

export async function handleRequest(req: Request, res: Response) {
  let tempDir: string | undefined
  try {
    if (!req.body) {
      return res.status(400).send({
        error: "Empty request",
      })
    }

    const { bb_version, inputs, circuit, stats = false, logging = false } = req.body

    const threads = req.body.threads !== undefined ? parseInt(req.body.threads) : undefined
    if (threads !== undefined && threads <= 0) {
      return res.status(400).send({
        error: "Threads parameter must be a positive number",
      })
    }
    if (!bb_version) {
      return res.status(400).send({
        error: "Missing bb_version in request body",
        supportedVersions: Object.keys(BB_VERSIONS),
      })
    }
    if (!inputs) {
      return res.status(400).send({
        error: "Missing inputs field in request body",
      })
    }
    if (!circuit) {
      return res.status(400).send({
        error: "Missing circuit field in request body",
      })
    }

    const mappedPath = BB_VERSIONS[bb_version as keyof typeof BB_VERSIONS]
    if (!mappedPath) {
      return res.status(400).send({
        error: `Unsupported bb version: ${bb_version}`,
        supportedVersions: Object.keys(BB_VERSIONS),
      })
    }
    const BB_BINARY_PATH = mappedPath

    if (!BB_BINARY_PATH) {
      return res.status(400).send({
        error:
          "bb binary path not set. Please provide bb_version in request body or set BB_BINARY_PATH environment variable",
        supportedVersions: Object.keys(BB_VERSIONS),
      })
    }

    // Create temporary directory
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "prover-"))
    const witnessPath = path.join(tempDir, "witness.gz")
    const circuitPath = path.join(tempDir, "circuit.json")
    const proofPath = path.join(tempDir, "proof")

    await writeFileAsync(circuitPath, JSON.stringify(circuit))

    // Generate witness map from the inputs and the circuit parameters (from the abi)
    const witnessMap = generateWitnessMap(inputs, circuit.abi.parameters)

    // Execute the circuit with the witness map
    const executionResult = await executeCircuit(
      Buffer.from(circuit.bytecode, "base64"),
      witnessMap,
      async (foreignCall) => {
        return []
      },
    )

    // Compress the witness
    const witnessBytes = await compressWitness(executionResult)

    // Write the witness to a file
    await writeFileAsync(witnessPath, witnessBytes)

    // Execute bb prove_ultra_honk command
    const threadParam = threads ? `--threads ${threads} ` : ""
    const timePrefix = stats ? "/bin/time -v " : ""

    const proveCommand = `${timePrefix}${BB_BINARY_PATH} prove --scheme ultra_honk ${threadParam}-v -b ${circuitPath} -w ${witnessPath} -o ${tempDir}`

    console.log(`Executing: ${proveCommand}`)
    const startTime = Date.now()
    const { stdout, stderr } = await execAsync(proveCommand, {
      cwd: tempDir,
    })
    const endTime = Date.now()
    const elapsedTime = (endTime - startTime) / 1000
    console.log(`Elapsed time: ${elapsedTime.toFixed(2)} seconds`)

    if (logging === true) {
      console.log("stdout:", stdout)
      console.log("stderr:", stderr)
    }

    // Check if proof file was created
    if (!fs.existsSync(proofPath)) {
      throw new Error("Proof file was not created")
    }
    // Read the proof file and encode as base64
    const proofHex = fs.readFileSync(proofPath).toString("hex")

    return res.status(200).send({
      success: true,
      proof: proofHex,
      bbout: stderr || "",
    })
  } catch (error) {
    console.error("Error executing bb:", error)
    return res.status(500).send({
      error: "Failed to execute bb prove_ultra_honk",
      details: error instanceof Error ? error.message : "Unknown error",
    })
  } finally {
    // Clean up temporary directory
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true })
    }
  }
}
