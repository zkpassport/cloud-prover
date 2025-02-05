import express, { Request, Response } from "express"
import { handleRequest } from "./handler"

const app = express()
app.use(express.json())
const port = process.env.PORT || 3000

app.get("/", (req: Request, res: Response) => {
  res.send("Hello from Fargate!!!")
})

app.post("/prove", async (req: Request, res: Response) => {
  await handleRequest(req, res)
})

// Start the server
const server = app.listen(port, () => {
  console.log(`Server running on port ${port}`)
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
