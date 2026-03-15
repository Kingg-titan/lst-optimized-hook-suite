import { BrowserProvider, Contract, formatEther } from "ethers";
import "./style.css";

const controllerAbi = [
  "function getPoolConfig(bytes32) view returns (tuple(bool enabled,address rebasingToken,bool rebasingTokenIsCurrency0,uint16 maxIndexDeltaBps,uint16 yieldSplitBps,uint8 distributionMode,uint256 maxAmountIn,uint256 cooldownMaxAmountIn,uint16 maxImpactBps,uint16 cooldownMaxImpactBps,uint40 cooldownSeconds,uint40 hysteresisSeconds))",
  "function getPoolAccounting(bytes32) view returns (tuple(uint256 lastYieldDeltaRaw,uint256 cumulativeYieldRaw,uint256 cumulativeDistributedRaw,uint256 lastObservedIndex))"
];

const hookAbi = [
  "function getGuardrailState(bytes32) view returns (tuple(uint40 cooldownEnd,uint40 hysteresisEnd,int24 lastObservedTick,uint40 lastObservedAt))",
  "function constrainedSwapCount(bytes32) view returns (uint256)"
];

const rebasingAbi = [
  "function index() view returns (uint256)",
  "function rebaseByBps(uint16)",
  "function balanceOf(address) view returns (uint256)"
];

const output = document.getElementById("output");
const walletLabel = document.getElementById("walletLabel");

let signer;

function getInput(id) {
  return document.getElementById(id).value.trim();
}

function log(data) {
  output.textContent = typeof data === "string" ? data : JSON.stringify(data, null, 2);
}

async function connect() {
  if (!window.ethereum) {
    log("No wallet found. Install a browser wallet and retry.");
    return;
  }
  const provider = new BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  walletLabel.textContent = await signer.getAddress();
}

async function triggerRebase() {
  if (!signer) return log("Connect wallet first.");

  const token = new Contract(getInput("rebasingToken"), rebasingAbi, signer);
  const bps = Number(getInput("rebaseBps"));

  const tx = await token.rebaseByBps(bps);
  const receipt = await tx.wait();

  const idx = await token.index();
  log({ action: "rebase", txHash: receipt.hash, indexAfter: idx.toString() });
}

async function evaluate() {
  if (!signer) return log("Connect wallet first.");

  const poolId = getInput("poolId");
  const controller = new Contract(getInput("controllerAddress"), controllerAbi, signer);
  const hook = new Contract(getInput("hookAddress"), hookAbi, signer);
  const token = new Contract(getInput("rebasingToken"), rebasingAbi, signer);

  const [cfg, accounting, state, idx, constrainedCount] = await Promise.all([
    controller.getPoolConfig(poolId),
    controller.getPoolAccounting(poolId),
    hook.getGuardrailState(poolId),
    token.index(),
    hook.constrainedSwapCount(poolId)
  ]);

  const now = Math.floor(Date.now() / 1000);
  const inCooldown = now < Number(state.cooldownEnd);
  const activeLimit = inCooldown ? cfg.cooldownMaxAmountIn : cfg.maxAmountIn;
  const amountIn = BigInt(getInput("swapAmount"));

  log({
    timestamp: now,
    index: idx.toString(),
    inCooldown,
    requestedAmountIn: amountIn.toString(),
    activeMaxAmountIn: activeLimit.toString(),
    wouldPassAmountCheck: amountIn <= activeLimit,
    constrainedSwapCount: constrainedCount.toString(),
    guardrailState: {
      cooldownEnd: state.cooldownEnd.toString(),
      hysteresisEnd: state.hysteresisEnd.toString(),
      lastObservedTick: state.lastObservedTick,
      lastObservedAt: state.lastObservedAt.toString()
    },
    accounting: {
      lastYieldDeltaRaw: accounting.lastYieldDeltaRaw.toString(),
      cumulativeYieldRaw: accounting.cumulativeYieldRaw.toString(),
      cumulativeDistributedRaw: accounting.cumulativeDistributedRaw.toString(),
      lastObservedIndex: accounting.lastObservedIndex.toString(),
      cumulativeYieldReadable: formatEther(accounting.cumulativeYieldRaw)
    }
  });
}

document.getElementById("connectBtn").addEventListener("click", connect);
document.getElementById("rebaseBtn").addEventListener("click", triggerRebase);
document.getElementById("evaluateBtn").addEventListener("click", evaluate);
