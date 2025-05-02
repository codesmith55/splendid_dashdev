import { Hono } from "hono";
import { handle } from "hono/vercel";

import auth from "@/features/auth/server/route";
import workspaces from "@/features/workspaces/server/route";

export const runtime = "edge";

const app = new Hono().basePath("/api");

const routes = app.route("/auth", auth).route("/workspaces", workspaces);//have to chain all the .routes here into one constant first time to keep typedefs


app.get("/hello", (c) => {
    return c.json({ hello: "world" })
});

app.get("/project/:projectId", (c) => {
    const { projectId } = c.req.param();

    return c.json({ project: projectId })
});

export const GET = handle(app);
export const POST = handle(app);

export type AppType = typeof routes;


