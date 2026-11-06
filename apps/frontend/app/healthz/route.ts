// ALB health check for the frontend. Lives outside /api because the load
// balancer sends /api/* to the backend.
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok", version: process.env.APP_VERSION ?? "dev" });
}
