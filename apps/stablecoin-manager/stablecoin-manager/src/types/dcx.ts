export type MoneyType = 'private' | 'defi' | 'cbdc' | 'wholesale' | 'platform';

export interface DigitalCurrency {
  id: string;                  // stablecoins: symbol ("USDC"), CBDCs: code ("e-CNY"), platforms: slug
  name: string;                // "USD Coin", "Digital Yuan", "Fnality USC"
  type: MoneyType;             // 'private' | 'defi' | 'cbdc' | 'wholesale' | 'platform'
  issuer: string;              // Circle, Tether Ltd, PBOC, Fnality International
  custodian?: string;          // BNY Mellon, Cantor Fitzgerald, Central Bank UAE, etc.
  chains?: ChainBinding[];     // contracts/addresses per chain or "n/a" for CBDCs/wholesale
  price?: number;              // from LiveDataService (coingecko/issuer)
  peg?: string;                // 'USD','CNH','EUR'
  reserveRatio?: number;       // e.g., 1.0013
  treasuryPct?: number;        // % of reserves in USTs/T-Bills
  circulationUsd?: number;
  reservesUsd?: number;
  attestation?: AttestationRef;
  policy?: PolicyRef;
  riskScore?: RiskScore;       // computed (see Scoring)
  status?: 'excellent' | 'good' | 'fair' | 'watch' | 'restricted';
}

export interface ChainBinding {
  chain: string;               // 'ethereum','polygon','arbitrum','sui','rln','fnality','rtgs'
  standard?: string;           // 'ERC-20','ERC-1400','SPL','Sui coin', 'bank ledger'
  address?: string;            // contract address (if on-chain)
  xrplIssuer?: string;         // XRPL issuer address
  xrplCurrency?: string;       // XRPL currency code
  notes?: string;             // e.g., "rebasing (STBT)", "wrapped non-rebase (wSTBT)"
}

export interface AttestationRef {
  url?: string;                // latest attestation/report PDF or API endpoint
  lastAuditDate?: string;      // ISO date
  lastAttestedAt?: string;     // ISO date
  cadence?: 'daily'|'weekly'|'monthly'|'ad-hoc';
  auditor?: string;            // e.g., Deloitte, Withum, Armanino, internal
}

export interface PolicyRef {
  kyc: 'retail'|'accredited'|'institutional'|'restricted';
  sanctions: 'us'|'uk'|'eu'|'multi'|'custom';
  redemption: 't+0'|'t+1'|'t+2'|'manual'|'n/a';
  feesBps?: number;
  jurisdiction?: string;       // NYDFS, MAS, FCA, etc.
}

export interface RiskScore {
  reserve: number;             // reserve ratio + composition
  transparency: number;        // attestation cadence + auditor quality
  custody: number;             // custodian class + bankruptcy remoteness
  peg: number;                // price deviation + liquidity depth
  chain: number;              // chain risk/compliance
  policy: number;             // KYC/sanctions program strength
  composite: number;          // 0–100
}
