import { describe, expect, test } from "bun:test"
import { Request, Response } from "express"
import { RegistryClient } from "@zkpassport/registry"
import { handleRequest } from "../src/handler"

async function prove(body: object) {
  const response: { statusCode?: number; body?: unknown } = {}
  const res = {
    status(code: number) {
      response.statusCode = code
      return this
    },
    send(data: unknown) {
      response.body = data
      return this
    },
  } as Response

  await handleRequest({ body } as Request, res)
  return response
}

describe("bb version check", () => {
  test("a bb_version other than the circuit's is rejected before proving", async () => {
    const registry = new RegistryClient({ chainId: 11155111 })
    const manifest = await registry.getCircuitManifest(undefined, { version: "0.21.1" })
    const circuit = await registry.getPackagedCircuit("outer_count_5", manifest, {
      validate: false,
    })
    expect(circuit.bb_version).toBe("5.0.0")

    const response = await prove({
      bb_version: "6.0.0",
      inputs: {},
      circuit: { bytecode: circuit.bytecode, abi: circuit.abi, hash: circuit.hash },
      vkey: circuit.vkey,
      circuit_root: manifest.root,
      circuit_name: circuit.name,
    })

    expect(response).toEqual({
      statusCode: 400,
      body: { error: "bb_version 6.0.0 does not match outer_count_5's bb version 5.0.0" },
    })
  }, 60_000)
})
