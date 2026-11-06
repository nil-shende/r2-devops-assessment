/** @type {import('next').NextConfig} */
const nextConfig = {
  // "standalone" produces a self-contained server (server.js + minimal node_modules).
  // The SAME build output is used by the Docker image (ECS) and by the
  // CodeDeploy bundle (EC2), so both deployment approaches run identical code.
  output: "standalone",
  poweredByHeader: false,
  reactStrictMode: true,
};
export default nextConfig;
