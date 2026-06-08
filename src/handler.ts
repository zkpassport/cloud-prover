import { exec } from "child_process"
import { promisify } from "util"
import * as fs from "fs"
import * as os from "os"
import * as path from "path"
import { Request, Response } from "express"
import {
  executeCircuit as executeCircuitV4_2_0_aztecnr_rc_2,
  compressWitness as compressWitnessV4_2_0_aztecnr_rc_2,
} from "@aztec/noir-acvm_js-4.2.0-aztecnr-rc.2"
import { generateWitnessMap } from "./utils"
import { RegistryClient } from "@zkpassport/registry"
import { CircuitManifest, PackagedCircuit } from "@zkpassport/utils"

// Binary path per bb version. Override per-version via env vars for local dev.
// Defaults match the Dockerfile layout. To add a version (e.g. v5), add an entry
// here, an acvm_js import, and a branch in executeCircuit/compressWitness below.
const BB_VERSIONS: Record<string, string> = {
  "4.2.0-aztecnr-rc.2":
    process.env.BB_BIN_V4_2_0_AZTECNR_RC_2 ?? "bb_v4.2.0-aztecnr-rc.2",
}

const execAsync = promisify(exec)
const writeFileAsync = promisify(fs.writeFile)

const executeCircuit = (bb_version: string) => {
  if (bb_version === "4.2.0-aztecnr-rc.2") {
    return executeCircuitV4_2_0_aztecnr_rc_2
  } else {
    throw new Error(`Unsupported bb version: ${bb_version}`)
  }
}

const compressWitness = (bb_version: string) => {
  if (bb_version === "4.2.0-aztecnr-rc.2") {
    return compressWitnessV4_2_0_aztecnr_rc_2
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
  // Only outer, DSC signature verification and facematch circuits should be used in the cloud prover
  if (
    !circuitName.startsWith("outer") &&
    !circuitName.startsWith("facematch") &&
    !circuitName.startsWith("sig_check_dsc")
  ) {
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
  let witnessGenMs: number | null = null
  const reqStart = Date.now()
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
      const witnessGenStart = Date.now()
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
      witnessGenMs = Date.now() - witnessGenStart
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
    const bbProveMs = endTime - startTime

    // bb's `-v` output carries the in-bb phase timings (CRS load, proving-key
    // construction, proving). Proof volume is low, so always surface it for
    // drill-down in Cloud Logging.
    if (stderr) console.log(`[bb_verbose] ${stderr}`)
    if (logging === true) console.log("stdout:", stdout)

    // Check if proof file was created
    if (!fs.existsSync(proofPath)) {
      throw new Error("Proof file was not created")
    }
    // Read the proof file and encode as base64
    const proofHex = fs.readFileSync(proofPath).toString("hex")
    const publicInputs = fs.readFileSync(publicInputPath).toString("hex")

    // Structured per-proof timing — becomes queryable jsonPayload.* fields in
    // Cloud Logging, and the basis for log-based metrics in Cloud Monitoring.
    console.log(
      JSON.stringify({
        event: "proof_generated",
        circuit_name,
        bb_version,
        evm,
        disable_zk,
        witness_source: witness ? "provided" : "generated",
        witness_gen_ms: witnessGenMs,
        bb_prove_ms: bbProveMs,
        total_ms: Date.now() - reqStart,
      }),
    )

    return res.status(200).send({
      success: true,
      proof: proofHex,
      bbout: stderr || "",
      public_inputs: publicInputs,
    })
  } catch (error) {
    console.error(
      JSON.stringify({
        event: "proof_failed",
        witness_gen_ms: witnessGenMs,
        total_ms: Date.now() - reqStart,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
    )
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
