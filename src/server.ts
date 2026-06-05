import express, { Request, Response } from "express"
import http from "node:http"
import client from "prom-client"
import { handleRequest } from "./handler"

const app = express()
app.use(
  express.json({
    limit: "50mb",
  }),
)
const port = process.env.PORT || 3000

app.get("/", (req: Request, res: Response) => {
  res.send("ZKPassport cloud prover")
})

app.post("/prove", async (req: Request, res: Response) => {
  await handleRequest(req, res)
})

// Start the server
const server = app.listen(port, () => {
  console.log(`Server running on port ${port}`)
})

client.collectDefaultMetrics()
const metricsPort = Number(process.env.METRICS_PORT ?? 9090)
const metricsServer = http.createServer(async (req, res) => {
  if (req.url === "/metrics") {
    res.setHeader("Content-Type", client.register.contentType)
    res.end(await client.register.metrics())
    return
  }
  res.statusCode = 404
  res.end()
})
metricsServer.listen(metricsPort, () => {
  console.log(`Metrics server running on port ${metricsPort}`)
})

// Handle graceful shutdown
process.on("SIGINT", () => {
  console.log("\nReceived SIGINT (Ctrl+C). Gracefully shutting down...")
  server.close(() => {
    console.log("Server closed. Exiting process.")
    process.exit(0)
  })
  // If server hasn't closed in 5 seconds, force exit
  setTimeout(() => {
    console.log("Could not close server gracefully. Force exiting...")
    process.exit(1)
  }, 5000)
})
