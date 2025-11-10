/**
 * RLUSD Integration Types
 * Defines types for Ripple USD across XRPL and Ethereum networks
 */

export enum RLUSDNetwork {
  XRPL_MAINNET = "xrpl-mainnet",
  XRPL_TESTNET = "xrpl-testnet",
  ETHEREUM_MAINNET = "ethereum-mainnet",
}

export interface RLUSDConfig {
  symbol: "RLUSD";
  displayName: "Ripple USD";
  class: "EXTERNAL_STABLECOIN";
  decimals: 18;
  networks: {
    [RLUSDNetwork.ETHEREUM_MAINNET]: {
      type: "ERC20";
      proxyAddress: string;
      implementationAddress?: string;
    };
    [RLUSDNetwork.XRPL_MAINNET]: {
      type: "XRPL_ISSUED";
      currency: "RLUSD";
      issuer: string;
    };
    [RLUSDNetwork.XRPL_TESTNET]: {
      type: "XRPL_ISSUED";
      currency: "RLUSD";
      issuer: string;
    };
  };
  risk: {
    ltv: number;
    haircut: number;
    category: "TIER1_STABLE";
  };
}

export interface RLUSDBalance {
  network: RLUSDNetwork;
  balance: string;
  usdValue: string;
  lastUpdated: Date;
}

export interface RLUSDTransfer {
  id: string;
  network: RLUSDNetwork;
  from: string;
  to: string;
  amount: string;
  status: "pending" | "confirmed" | "failed";
  txHash?: string;
  timestamp: Date;
}

export interface RLUSDSwapRequest {
  fromAsset: string;
  toAsset: "RLUSD";
  network: RLUSDNetwork;
  amount: string;
  slippageBps: number;
  recipient?: string;
}

export interface RLUSDSwapResponse {
  swapId: string;
  fromAsset: string;
  toAsset: "RLUSD";
  fromAmount: string;
  toAmount: string;
  network: RLUSDNetwork;
  rate: string;
  fees: {
    networkFee: string;
    protocolFee: string;
    total: string;
  };
  estimatedTime: number;
  expiresAt: Date;
}

export interface RLUSDPriceData {
  price: string;
  deviation: number;
  timestamp: Date;
  sources: Array<{
    oracle: string;
    price: string;
    weight: number;
  }>;
}

/**
 * Asset ID enum matching Solidity Types.sol
 */
export enum AssetId {
  USDC = "USDC",
  USDT = "USDT",
  TGUSD = "TGUSD",
  FTHUSD = "FTHUSD",
  RLUSD = "RLUSD",
}

/**
 * Settlement rail types
 */
export enum SettlementRail {
  SWIFT_GPI = "SWIFT_GPI",
  CHAINLINK_CCIP = "CHAINLINK_CCIP",
  CIRCLE_CCTP = "CIRCLE_CCTP",
  BIS_AGORA = "BIS_AGORA",
  RLN_MULTI_CBDC = "RLN_MULTI_CBDC",
  FNALITY = "FNALITY",
  MIDNIGHT = "MIDNIGHT",
  XRPL = "XRPL",
}

/**
 * Extended settlement config with RLUSD support
 */
export interface SettlementConfig {
  rail: SettlementRail;
  asset: AssetId;
  network?: RLUSDNetwork;
  priority: number;
  enabled: boolean;
  fees: {
    fixed: string;
    bps: number;
  };
  limits: {
    min: string;
    max: string;
    daily: string;
  };
}

/**
 * RLUSD Trustline status on XRPL
 */
export interface XRPLTrustlineStatus {
  account: string;
  currency: "RLUSD";
  issuer: string;
  balance: string;
  limit: string;
  limitPeer: string;
  qualityIn: number;
  qualityOut: number;
  noRipple: boolean;
  authorized: boolean;
  frozen: boolean;
}

/**
 * Complete RLUSD account state
 */
export interface RLUSDAccountState {
  address: string;
  balances: RLUSDBalance[];
  totalUsdValue: string;
  trustlines: {
    xrplMainnet?: XRPLTrustlineStatus;
    xrplTestnet?: XRPLTrustlineStatus;
  };
  recentTransfers: RLUSDTransfer[];
  allowedNetworks: RLUSDNetwork[];
}
