#!/usr/bin/env node

/**
 * Script utilitário em Node.js para configurar regras de CORS no bucket do Garage S3.
 * Ele tenta ler o arquivo `.env.s3` da pasta local para aplicar as credenciais.
 * 
 * Requisitos:
 *   npm install @aws-sdk/client-s3
 * 
 * Uso:
 *   node configure-cors.js
 */

const { S3Client, PutBucketCorsCommand } = require("@aws-sdk/client-s3");
const fs = require("fs");
const path = require("path");

// Carregar variáveis do arquivo .env.s3 se ele existir localmente
const envPath = path.join(process.cwd(), ".env.s3");
if (fs.existsSync(envPath)) {
  console.log("Carregando credenciais do arquivo .env.s3...");
  const envContent = fs.readFileSync(envPath, "utf8");
  envContent.split("\n").forEach((line) => {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith("#")) {
      const [key, ...values] = trimmed.split("=");
      if (key && values.length > 0) {
        process.env[key.trim()] = values.join("=").trim();
      }
    }
  });
}

// Parâmetros do Garage S3
const endpoint = process.env.AWS_ENDPOINT_URL || "http://localhost:3900";
const region = process.env.AWS_DEFAULT_REGION || "sa-east-1";
const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
const bucketName = process.env.S3_BUCKET_NAME;

if (!accessKeyId || !secretAccessKey || !bucketName) {
  console.error("\n[Erro] Variáveis obrigatórias em falta!");
  console.error("Certifique-se de que o arquivo '.env.s3' está na mesma pasta onde este script foi chamado,");
  console.error("ou configure as variáveis abaixo no seu ambiente:");
  console.error("  - AWS_ACCESS_KEY_ID");
  console.error("  - AWS_SECRET_ACCESS_KEY");
  console.error("  - S3_BUCKET_NAME");
  console.error("  - AWS_ENDPOINT_URL (opcional, padrão: http://localhost:3900)");
  console.error("  - AWS_DEFAULT_REGION (opcional, padrão: sa-east-1)\n");
  process.exit(1);
}

// Configurar o cliente S3 apontando para o Garage local/produção
const s3Client = new S3Client({
  endpoint,
  region,
  credentials: {
    accessKeyId,
    secretAccessKey,
  },
  forcePathStyle: true, // Obrigatório para o Garage
});

// Configuração padrão de CORS para liberar o acesso ao browser/frontend
const corsConfiguration = {
  Bucket: bucketName,
  CORSConfiguration: {
    CORSRules: [
      {
        AllowedHeaders: ["*"],
        AllowedMethods: ["GET", "PUT", "POST", "DELETE", "HEAD"],
        AllowedOrigins: ["*"], // Em produção, substitua pelo domínio do seu frontend (ex: https://seuapp.com)
        ExposeHeaders: ["ETag"],
        MaxAgeSeconds: 3600,
      },
    ],
  },
};

async function run() {
  try {
    console.log(`Conectando ao Garage em: ${endpoint}`);
    console.log(`Aplicando configuração de CORS no bucket: "${bucketName}"...`);
    
    await s3Client.send(new PutBucketCorsCommand(corsConfiguration));
    
    console.log(`\n✔ CORS configurado com sucesso para o bucket "${bucketName}"!`);
    console.log("Agora o seu navegador tem permissão para fazer uploads diretos (ex: via Presigned URLs) para o Garage.");
  } catch (error) {
    console.error("\n[Erro] Falha ao configurar CORS via S3 API:");
    console.error(error.message || error);
    process.exit(1);
  }
}

run();
