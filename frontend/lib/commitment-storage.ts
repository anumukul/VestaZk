import { CommitmentData } from "./types";

const STORAGE_PREFIX = "vestazk-commitment-";

export function saveCommitmentData(address: string, data: CommitmentData): void {
  const key = `${STORAGE_PREFIX}${address}`;
  localStorage.setItem(key, JSON.stringify(data));
}

export function getCommitmentData(address: string): CommitmentData | null {
  const key = `${STORAGE_PREFIX}${address}`;
  const stored = localStorage.getItem(key);
  if (!stored) return null;
  
  try {
    return JSON.parse(stored) as CommitmentData;
  } catch {
    return null;
  }
}

export function removeCommitmentData(address: string): void {
  const key = `${STORAGE_PREFIX}${address}`;
  localStorage.removeItem(key);
}

export function hasCommitmentData(address: string): boolean {
  return getCommitmentData(address) !== null;
}
