import Items from "./items";

// Render on every request so runtime env vars (set by ECS / systemd) are read
// at request time, not baked in at build time.
export const dynamic = "force-dynamic";

export default function Home() {
  const env = process.env.APP_ENV ?? "local";
  const version = process.env.APP_VERSION ?? "dev";
  const target = process.env.DEPLOYMENT_TARGET ?? "local";

  return (
    <main>
      <header>
        <h1>R2 DevOps Assessment</h1>
        <p className="muted">Next.js frontend · Python (FastAPI) backend · PostgreSQL (RDS)</p>
      </header>

      <section className="grid">
        <div className="card">
          <span className="label">Environment</span>
          <strong>{env}</strong>
        </div>
        <div className="card">
          <span className="label">Frontend runs on</span>
          <strong>{target === "ecs" ? "ECS (container)" : target === "ec2" ? "EC2 (no container)" : target}</strong>
        </div>
        <div className="card">
          <span className="label">Frontend version</span>
          <strong className="mono">{version.slice(0, 12)}</strong>
        </div>
      </section>

      <Items />
    </main>
  );
}
