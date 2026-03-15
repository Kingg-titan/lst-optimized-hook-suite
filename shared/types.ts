export type Address = `0x${string}`;

export interface DeployedContracts {
  poolManager: Address;
  hook: Address;
  controller: Address;
  mockRebasingLST: Address;
  mockNonRebasingLST: Address;
}

export interface PoolConfigInput {
  enabled: boolean;
  rebasingToken: Address;
  rebasingTokenIsCurrency0: boolean;
  maxIndexDeltaBps: number;
  yieldSplitBps: number;
  maxAmountIn: string;
  cooldownMaxAmountIn: string;
  maxImpactBps: number;
  cooldownMaxImpactBps: number;
  cooldownSeconds: number;
  hysteresisSeconds: number;
}
