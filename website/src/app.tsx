import { Spiceflow } from "spiceflow";
import { Head } from "spiceflow/react";
import { app as holocronApp } from "@holocron.so/vite/app";
import { HomePage } from "./home/HomePage";
import "./home/home.css";

export const app = new Spiceflow()
  .layout("/", async ({ children }) => {
    return (
      <html lang="en">
        <Head>
          <Head.Title>Hypnograph</Head.Title>
          <Head.Meta charSet="UTF-8" />
          <Head.Meta
            name="viewport"
            content="width=device-width, initial-scale=1"
          />
          <Head.Meta
            name="description"
            content="Hypnograph is a memory-forward visual instrument for macOS."
          />
          <Head.Meta name="theme-color" content="#0f1115" />
        </Head>
        <body>{children}</body>
      </html>
    );
  })
  .page("/", async () => {
    return <HomePage />;
  })
  .use(holocronApp);

app.listen(Number(process.env.PORT || 3000));

export default app;
