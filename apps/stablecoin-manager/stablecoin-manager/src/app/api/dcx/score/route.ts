import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET() {
  const items = await prisma.digitalCurrency.findMany({
    include: { attestation: true, policy: true }
  });

  const scored = items.map(x => {
    // Reserve score
    const reserve = Math.min(100, Math.max(0, (x.reserveRatio ?? 1) * 100));
    
    // Attestation age score
    const attAgeDays = x.attestation?.lastAttestedAt
      ? (Date.now() - new Date(x.attestation.lastAttestedAt).getTime()) / 86400000
      : 365;
    const transparency = attAgeDays <= 30 ? 90 : attAgeDays <= 60 ? 75 : 50;
    
    // Other component scores
    const custody = x.custodian ? 85 : 60;
    const peg = (x.price && Math.abs(1 - x.price) < 0.003) ? 90 : 70;
    const chain = x.chains?.length > 0 ? 80 : 65;
    const policy = x.policy?.kyc ? 85 : 60;

    // Composite score calculation
    const composite = Math.round(
      0.25*reserve + 0.2*transparency + 0.15*custody + 0.2*peg + 0.1*chain + 0.1*policy
    );

    return {
      id: x.id,
      name: x.name,
      composite,
      breakdown: {
        reserve,
        transparency,
        custody,
        peg,
        chain,
        policy
      }
    };
  });

  return NextResponse.json({ items: scored, ts: Date.now() });
}
