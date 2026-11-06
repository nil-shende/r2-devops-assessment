import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "R2 DevOps Assessment",
  description: "Next.js + Python + PostgreSQL on AWS",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
