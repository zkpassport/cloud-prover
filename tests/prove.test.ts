import { handleRequest as handler } from "../src/handler"
import { describe, test, expect, beforeAll, afterAll } from "bun:test"
import * as fs from "fs"
import * as path from "path"
import { exec } from "child_process"
import { promisify } from "util"
import * as os from "os"
import { Request, Response } from "express"

const BB_VERSION = "1.0.0-nightly.20250701"
const CIRCUIT = `simple_${BB_VERSION}`

const execAsync = promisify(exec)
const writeFileAsync = promisify(fs.writeFile)

describe("Handler tests", () => {
  test("should call local prove function with valid witness and circuit", async () => {
    // Load witness from file
    const witnessPath = path.join(__dirname, "fixtures", `${CIRCUIT}.gz`)
    const witnessBase64 = fs.readFileSync(witnessPath).toString("base64")
    // Load circuit from file
    const circuitPath = path.join(__dirname, "fixtures", `${CIRCUIT}.json`)
    const circuit = JSON.parse(fs.readFileSync(circuitPath).toString())
    // Mock Express request and response
    const mockReq = {
      body: {
        bb_version: BB_VERSION,
        witness: witnessBase64,
        circuit: circuit,
        recursive: false,
      },
    } as Request
    let responseData: any = {}
    const mockRes = {
      status: function (code: number) {
        responseData.statusCode = code
        return this
      },
      send: function (data: any) {
        responseData = { ...responseData, ...data }
        return this
      },
      json: function (data: any) {
        responseData = { ...responseData, ...data }
        return this
      },
    } as Response

    await handler(mockReq, mockRes)

    // Check if the response has the expected structure
    expect(responseData.statusCode).toBe(200)
    expect(responseData).toHaveProperty("success")
    expect(responseData).toHaveProperty("proof")
    expect(responseData).toHaveProperty("public_inputs")
    expect(responseData.success).toBe(true)

    // Create a temporary directory for verification
    const verifyDir = fs.mkdtempSync(path.join(os.tmpdir(), "verify-"))
    const verifyProofPath = path.join(verifyDir, "output.proof")
    const publicInputsPath = path.join(verifyDir, "public_inputs")

    // Write the proof to a file
    await writeFileAsync(verifyProofPath, Buffer.from(responseData.proof, "hex"))
    await writeFileAsync(publicInputsPath, Buffer.from(responseData.public_inputs, "hex"))
    // Run verification command
    const vkeyPath = path.join(__dirname, "fixtures", `${CIRCUIT}.vkey`)
    const verifyCommand = `bb verify -v -p ${verifyProofPath} -k ${vkeyPath} -i ${publicInputsPath}`
    console.log(`Executing verify command: ${verifyCommand}`)
    const { stdout: _, stderr } = await execAsync(verifyCommand, {
      cwd: verifyDir,
    })

    // Assert that verification succeeded
    expect(stderr).toContain("verified: 1")
  }, 120000)

  test("should call remote prove endpoint with valid witness and circuit", async () => {
    // Load witness from file
    const witnessPath = path.join(__dirname, "fixtures", `${CIRCUIT}.gz`)
    const witnessBase64 = fs.readFileSync(witnessPath).toString("base64")
    // Load circuit from file
    const circuitPath = path.join(__dirname, "fixtures", `${CIRCUIT}.json`)
    const circuit = JSON.parse(fs.readFileSync(circuitPath).toString())
    // Call the remote endpoint
    const response = await fetch(
      // "https://prove.zkpassport.id/prove",
      "http://localhost:3000/prove",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          bb_version: BB_VERSION,
          witness: witnessBase64,
          circuit,
          recursive: false,
        }),
      },
    )

    const remoteResponseData = await response.json()
    console.log("Remote response:", remoteResponseData)
    expect(response.status).toBe(200)

    expect(remoteResponseData).toHaveProperty("success")
    expect(remoteResponseData).toHaveProperty("proof")
    expect(remoteResponseData).toHaveProperty("public_inputs")
    expect(remoteResponseData.success).toBe(true)

    // Create temporary directory for verification
    const verifyDir = fs.mkdtempSync(path.join(os.tmpdir(), "verify-"))
    const verifyProofPath = path.join(verifyDir, "output.proof")
    const publicInputsPath = path.join(verifyDir, "public_inputs")

    // Save proof to file and verify
    await writeFileAsync(verifyProofPath, Buffer.from(remoteResponseData.proof, "hex"))
    await writeFileAsync(publicInputsPath, Buffer.from(remoteResponseData.public_inputs, "hex"))
    const vkeyPath = path.join(__dirname, "fixtures", `${CIRCUIT}.vkey`)
    const verifyCommand = `bb verify -v -p ${verifyProofPath} -k ${vkeyPath} -i ${publicInputsPath}`
    console.log(`Executing verify command: ${verifyCommand}`)
    const { stdout: _, stderr } = await execAsync(verifyCommand, {
      cwd: verifyDir,
    })

    // Clean up temporary directory
    if (verifyDir && fs.existsSync(verifyDir)) {
      fs.rmSync(verifyDir, { force: true, recursive: true })
    }

    expect(stderr).toContain("verified: 1")
  }, 120000)
})
