import { PrismaClient } from '@prisma/client';
import yaml from 'js-yaml';
import fs from 'fs';
import path from 'path';

const prisma = new PrismaClient();

async function main() {
  const doc = yaml.load(
    fs.readFileSync(path.join(process.cwd(), 'data', 'dcx.registry.yaml'), 'utf8')
  ) as any[];

  for (const row of doc) {
    const att = row.attestation
      ? await prisma.attestation.create({
          data: {
            url: row.attestation.url ?? null,
            auditor: row.attestation.auditor ?? null,
            cadence: row.attestation.cadence ?? null,
            lastAuditDate: row.attestation.lastAuditDate ? new Date(row.attestation.lastAuditDate) : null,
            lastAttestedAt: row.attestation.lastAttestedAt ? new Date(row.attestation.lastAttestedAt) : null
          }
        })
      : null;

    const pol = row.policy
      ? await prisma.policy.create({
          data: {
            kyc: row.policy.kyc,
            sanctions: row.policy.sanctions,
            redemption: row.policy.redemption,
            feesBps: row.policy.feesBps ?? null,
            jurisdiction: row.policy.jurisdiction ?? null
          }
        })
      : null;

    await prisma.digitalCurrency.create({
      data: {
        id: row.id,
        name: row.name,
        type: row.type,
        issuer: row.issuer,
        custodian: row.custodian ?? null,
        peg: row.peg ?? null,
        attestationId: att?.id ?? null,
        policyId: pol?.id ?? null,
        chains: {
          create: (row.chains ?? []).map((c: any) => ({
            chain: c.chain,
            standard: c.standard ?? null,
            address: c.address ?? null,
            notes: c.notes ?? null
          }))
        }
      }
    });
  }

  console.log('Seed completed successfully');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
