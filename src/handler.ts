import { exec } from "child_process"
import { promisify } from "util"
import * as fs from "fs"
import * as os from "os"
import * as path from "path"
import { Request, Response } from "express"
import {
  executeCircuit as executeCircuitV2_0_3,
  compressWitness as compressWitnessV2_0_3,
} from "@aztec/noir-acvm_js-2.0.3"
import {
  executeCircuit as executeCircuitV1_0_0_nightly_20250723,
  compressWitness as compressWitnessV1_0_0_nightly_20250723,
} from "@aztec/noir-acvm_js-1.0.0-nightly.20250723"
import { generateWitnessMap } from "./utils"
import { RegistryClient } from "@zkpassport/registry"
import { CircuitManifest, PackagedCircuit } from "@zkpassport/utils"

const BB_VERSIONS = {
  "1.0.0-nightly.20250723": "bb_v1.0.0-nightly.20250723",
  "2.0.3": "bb",
}

const execAsync = promisify(exec)
const writeFileAsync = promisify(fs.writeFile)

const executeCircuit = (bb_version: string) => {
  if (bb_version === "1.0.0-nightly.20250723") {
    return executeCircuitV1_0_0_nightly_20250723
  } else if (bb_version === "2.0.3") {
    return executeCircuitV2_0_3
  } else {
    throw new Error(`Unsupported bb version: ${bb_version}`)
  }
}

const compressWitness = (bb_version: string) => {
  if (bb_version === "1.0.0-nightly.20250723") {
    return compressWitnessV1_0_0_nightly_20250723
  } else if (bb_version === "2.0.3") {
    return compressWitnessV2_0_3
  } else {
    throw new Error(`Unsupported bb version: ${bb_version}`)
  }
}

/**
 *
 * @param circuitRoot - The root of the circuit registry
 * @param vkey - The vkey of the circuit (in base64)
 * @param circuitName - The name of the circuit
 * @returns True if the circuit is valid (i.e. part of our circuit registry)
 */
async function isValidCircuit(circuitRoot: string, vkey: string, circuitName: string) {
  // Only outer and facematch circuits should be used in the cloud prover
  if (!circuitName.startsWith("outer") && !circuitName.startsWith("facematch")) {
    return false
  }

  const client = new RegistryClient({
    chainId: 11155111,
  })
  const manifest: CircuitManifest = await client.getCircuitManifest(circuitRoot)
  const packagedCircuit: PackagedCircuit = await client.getPackagedCircuit(circuitName, manifest, {
    validate: false,
  })
  return packagedCircuit.vkey == vkey
}

export async function handleRequest(req: Request, res: Response) {
  let tempDir: string | undefined
  try {
    if (!req.body) {
      return res.status(400).send({
        error: "Empty request",
      })
    }
    let {
      bb_version,
      witness,
      inputs,
      circuit,
      vkey,
      circuit_root,
      circuit_name,
      evm = false,
      disable_zk = false,
      stats = false,
      logging = false,
    } = req.body

    if (!bb_version) {
      return res.status(400).send({
        error: "Missing bb_version in request body",
        supportedVersions: Object.keys(BB_VERSIONS),
      })
    } else {
      bb_version = bb_version.toString()
      if (bb_version.startsWith("v")) {
        bb_version = bb_version.slice(1)
      }
    }
    if (!witness && !inputs) {
      return res.status(400).send({
        error: "Either witness or inputs field required",
      })
    }
    if (!circuit) {
      return res.status(400).send({
        error: "Missing circuit field in request body",
      })
    }
    if (!vkey) {
      return res.status(400).send({
        error: "Missing vkey field in request body",
      })
    }
    const isValid = await isValidCircuit(circuit_root, vkey, circuit_name)
    if (!isValid) {
      return res.status(400).send({
        error: "Unsupported circuit",
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
    const publicInputPath = path.join(tempDir, "public_inputs")
    const vkeyPath = path.join(tempDir, "vkey")

    await writeFileAsync(circuitPath, JSON.stringify(circuit))
    await writeFileAsync(vkeyPath, Buffer.from(vkey, "base64"))
    // Use solved witness if provided
    if (witness) {
      // Write base64-decoded witness to file
      const witnessBuffer = Buffer.from(witness, "base64")
      await writeFileAsync(witnessPath, witnessBuffer)
    }
    // Otherwise generate witness from inputs
    else {
      // Generate witness map from the inputs and the circuit parameters (from the abi)
      const witnessMap = generateWitnessMap(inputs, circuit.abi.parameters)
      // Execute the circuit with the witness map
      const executionResult = await executeCircuit(bb_version)(
        Buffer.from(circuit.bytecode, "base64"),
        witnessMap,
        async (foreignCall) => {
          return []
        },
      )
      // Compress the witness
      const witnessBytes = await compressWitness(bb_version)(executionResult)
      // Write the witness to a file
      await writeFileAsync(witnessPath, witnessBytes)
    }

    // Execute bb prove command
    const timePrefix = stats ? "/bin/time -v " : ""
    const proveCommand = `${timePrefix}${BB_BINARY_PATH} prove --scheme ultra_honk --vk_path ${vkeyPath} ${
      evm ? " --oracle_hash keccak" : ""
    } -v -b ${circuitPath} -w ${witnessPath} -o ${tempDir} ${disable_zk ? "--disable_zk" : ""}`

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
    const publicInputs = fs.readFileSync(publicInputPath).toString("hex")

    return res.status(200).send({
      success: true,
      proof: proofHex,
      bbout: stderr || "",
      public_inputs: publicInputs,
    })
  } catch (error) {
    console.error("Error executing bb:", error)
    return res.status(500).send({
      error: "Failed to execute bb prove",
      details: error instanceof Error ? error.message : "Unknown error",
    })
  } finally {
    // Clean up temporary directory
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true })
    }
  }
}
