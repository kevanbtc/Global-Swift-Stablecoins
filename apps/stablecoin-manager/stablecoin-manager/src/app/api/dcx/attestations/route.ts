import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET() {
  const items = await prisma.digitalCurrency.findMany({
    select: {
      id: true,
      name: true,
      attestation: true,
      reservesUsd: true,
      circulationUsd: true,
      reserveRatio: true,
      treasuryPct: true
    }
  });
  
  return NextResponse.json({ items });
}
