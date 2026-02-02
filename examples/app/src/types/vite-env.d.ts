/// <reference types="vite/client" />

interface ImportMeta {
  readonly env: {
    readonly VITE_API_BASE_URL?: string;
    readonly VITE_ETHSEPOLIA_RPC_URL?: string;
    readonly VITE_BASESEPOLIA_RPC_URL?: string;
    readonly VITE_TOPAZ_RPC_URL?: string;
    readonly [key: string]: string | undefined;
  };
}