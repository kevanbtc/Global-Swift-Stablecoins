import { NextResponse } from 'next/server';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function GET() {
  const items = await prisma.digitalCurrency.findMany({
    include: { chains: true, attestation: true, policy: true }
  });
  
  return NextResponse.json({ items, updatedAt: Date.now() });
}
