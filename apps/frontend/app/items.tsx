"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";

type Item = { id: number; name: string; created_at: string };
type Info = { environment: string; version: string; deployment_target: string; database: string };

// The browser calls the backend on the SAME origin: the ALB routes /api/* to the
// Python service. No CORS, no hard-coded backend URL baked into the bundle.
const API = "/api";

export default function Items() {
  const [info, setInfo] = useState<Info | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [i, l] = await Promise.all([fetch(`${API}/info`), fetch(`${API}/items`)]);
      setInfo(await i.json());
      if (l.ok) setItems(await l.json());
      setError(l.ok ? null : `Backend returned ${l.status}`);
    } catch {
      setError("Backend not reachable");
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function add(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    const r = await fetch(`${API}/items`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
    if (r.ok) {
      setName("");
      load();
    } else setError(`Could not save item (${r.status})`);
  }

  return (
    <>
      <section className="grid">
        <div className="card">
          <span className="label">Backend runs on</span>
          <strong>{info?.deployment_target ?? "…"}</strong>
        </div>
        <div className="card">
          <span className="label">Backend version</span>
          <strong className="mono">{info?.version?.slice(0, 12) ?? "…"}</strong>
        </div>
        <div className="card">
          <span className="label">Database</span>
          <strong className={info?.database === "connected" ? "ok" : "bad"}>{info?.database ?? "…"}</strong>
        </div>
      </section>

      <section className="card wide">
        <h2>Items (stored in PostgreSQL)</h2>
        <form onSubmit={add}>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Add an item" maxLength={200} />
          <button type="submit">Add</button>
        </form>
        {error && <p className="bad">{error}</p>}
        <ul>
          {items.map((i) => (
            <li key={i.id}>
              <span>{i.name}</span>
              <span className="muted mono">{new Date(i.created_at).toLocaleString()}</span>
            </li>
          ))}
          {items.length === 0 && !error && <li className="muted">No items yet.</li>}
        </ul>
      </section>
    </>
  );
}
