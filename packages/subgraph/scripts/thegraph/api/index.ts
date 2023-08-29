import { getNetworkConfig, listNetworks } from "../utils/config";

import { makeAws } from "./aws";
import { makeStudio } from "./studio";

export interface SubgraphVersion {
  id: number;
  label?: string;
  deploymentId: string;
  latestEthereumBlockNumber?: number;
  totalEthereumBlocksCount?: number;
  failed: boolean;
  synced: boolean;
}

export interface VersionUpdate {
  latestEthereumBlockNumber: number;
  totalEthereumBlocksCount: number;
  synced: boolean;
  failed: boolean;
}

type VersionUpdateCallback = (
  version: VersionUpdate,
  unsubscribe: () => void
) => Promise<void> | void;

export interface ISubgraph {
  name: string;
  network: string;
  graphNetwork: string;
  api: API;
}

export interface InnerAPI {
  getLatestVersion: (
    index?: number
  ) => Promise<SubgraphVersion | null | undefined>;

  watchVersionUpdate: (versionId: number, cb: VersionUpdateCallback) => void;

  args: {
    ipfs: () => string[];
    node: () => string[];
    product: () => string[];
  };
}
export interface API extends InnerAPI {
  waitForVersionSync: (
    versionId: number,
    cb?: VersionUpdateCallback
  ) => Promise<VersionUpdate>;
}

export const getSubgraphs = async (): Promise<ISubgraph[]> => {
  const networks = await listNetworks();
  const subgraphs: ISubgraph[] = [];
  for (const network of networks) {
    const networkConfig = await getNetworkConfig(network);

    if (!networkConfig.enabled) continue;

    let innerApi: InnerAPI;
    switch (networkConfig.product) {
      case "studio":
        innerApi = await makeStudio({
          name: networkConfig.name,
          network: networkConfig.network,
          logger: networkConfig?.logger
        });
        break;
      case "aws":
        innerApi = await makeAws({
          name: networkConfig.name,
          network: networkConfig.network,
          logger: networkConfig?.logger
        });
        break;
      default:
        throw new Error(
          `Unknown product (${networkConfig.product}) for subgraph "${networkConfig.name}"`
        );
    }

    subgraphs.push({
      name: networkConfig.name,
      network: network,
      graphNetwork: networkConfig.network,
      api: {
        ...innerApi,
        waitForVersionSync: (
          versionId: number,
          cb?: VersionUpdateCallback
        ): Promise<VersionUpdate> => {
          return new Promise((resolve, reject) => {
            innerApi.watchVersionUpdate(versionId, (version, unsubscribe) => {
              void cb?.(version, unsubscribe);

              if (version.failed) {
                unsubscribe();
                reject(`Version "${versionId} failed`);
              } else if (version.synced) {
                unsubscribe();
                resolve(version);
              }
            });
          });
        }
      }
    });
  }
  return subgraphs;
};
