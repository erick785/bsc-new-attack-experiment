# bsc-attack-experiment

## Introduction

Attack 1 Experiment layout:

Attack 1 starts a 21-validator local BSC cluster and splits it into two logical network partitions:

- Group A: node `0..9` plus the A-side instance of node `11`.
- Group B: node `10` and node `12..20`.
- Node `11` is intentionally duplicated. The original `node11` starts with Group A, while a copied `node11-b`
  instance is started later with Group B.

The script first builds the attack-1 `geth` binary and `create-validator`, resets the cluster, and starts the initial
21 validators. After the chain reaches height `201`, it adds extra validators on both sides:

- Group A adds validators `21..31`; registration transactions are sent through node0 RPC `8545`.
- Group B adds validators `32..41`; registration transactions are sent through node10 RPC `8555`.

After node0 reaches height `400`, the script starts the copied B-side `node11-b` instance with
`BSC_NETWORK_SPLIT_GROUP=B`. The experiment succeeds when both node0 and node10 observe a
`Parlia finalized block number changed` log after height `400`, showing that both partitions have advanced their
finalized block independently.

Simple sketch:

```text
  height
    ^
    |     Group A partition                              Group B partition
    |  node0..9 + node11(A)                         node10, node12..20
  0 |------------------------- common prefix -------------------------------> time
201 | + add validators 21..31 through node0 RPC 8545
    | + add validators 32..41 through node10 RPC 8555
400 | start copied node11-b with BSC_NETWORK_SPLIT_GROUP=B
    | A: finalized block changes on node0
    | B: finalized block changes on node10
    +---------------------------------------------------------------------> time
```


Attack 2 Experiment layout:

Attack 2 starts from the same 21-validator local BSC cluster, then creates two directed-propagation branches starting
at height `398`. During the manual schedule window, nodes do not broadcast blocks freely. Each scheduled block is sent
only to the next validator on that branch.

Before the split, the script starts the extra validators but keeps their registration transactions out of blocks. At
height `399`, each branch packs a different validator-add transaction set:

- A chain: `399(6c)` packs the transactions that add validators `21..31`.
- B chain: `399'(20)` packs the transactions that add validators `32..41`.

The manual routing schedule runs through `410/410'`. After that, the branch-specific validator sets continue sealing
naturally, while block propagation remains partitioned: A-side validators and A-side added validators only receive A
branch blocks, and B-side validators and B-side added validators only receive B branch blocks.

Two parallel chains:

```text
  difficulty :            2    →    1    →    2    →    1    →    2    →    1    →    2    →    1    →    2    →    1    →    1    →    2    →    1
  Chain A (no prime):  398(fe) → 399(6c) → 400(29) → 401(a8) → 402(50) → 403(bb) → 404(51) → 405(c1) → 406(5e) → 407(d3) → 408(f7) → 409(9b) → 410(3a)
```

```text
  difficulty :            1     →    2     →    1     →    2     →    1     →     2    →    1     →    2     →    1     →    1     →    2     →    1     →    2
  Chain B (prime):     398'(5f) → 399'(20) → 400'(9b) → 401'(3a) → 402'(ab) → 403'(511) → 404'(bc) → 405'(5a) → 406'(d2) → 407'(e9) → 408'(6c) → 409'(29) → 410'(a8)
```

Broadcast routing:

```text
  398  fe → 6c   |  398' 5f → 20
  399  6c → 29   |  399' 20 → 9b
  400  29 → a8   |  400' 9b → 3a
  401  a8 → 50   |  401' 3a → ab
  402  50 → bb   |  402' ab → 511
  403  bb → 51   |  403' 511 → bc
  404  51 → c1   |  404' bc → 5a
  405  c1 → 5e   |  405' 5a → d2
  406  5e → d3   |  406' d2 → e9
  407  d3 → f7   |  407' e9 → 6c
  408  f7 → 9b   |  408' 6c → 29
  409  9b → 3a   |  409' 29 → a8
  410  3a → ab   |  410' a8 → 50
  after 410, both branches continue sealing naturally with branch-local propagation.
```

Design notes:
For every scheduled reorg recipient, the TD of the recipient's current chain is strictly smaller than the broadcast
block's trueTD (= block.TD - block.Diff). Only under this condition will `chainSync.nextSyncOp` trigger the downloader
to fetch missing ancestors. After the recipient finishes the reorg, it produces the next scheduled block. From `411`
onward, the explicit sealing gate is lifted and each branch seals naturally, but block propagation remains isolated by
branch.

## 🚀 Quick Access

## 📦 Recommended Setup: Docker

### Prerequisites

### Running attack 1

### Running attack 2


## 🛠️ Optional: Manual Build & Execution

We also provide a fully manual setup method for users or reviewers who prefer to inspect and customize the testing environment (See [Appendix](#appendix)).

## 🧪 Attack Success Criteria

### For attack 1

The attack is considered successful when the script prints finalized block changes from both node0 and node10 after
height `400`, for example:

```text
[2026-05-04 17:51:43] node0 matched log line:
t=05-04|17:51:43.012 lvl=info msg="Parlia finalized block number changed" header=413 prevFinalized=396 newFinalized=411 targetNumber=412 sourceHash=0xa53b8dd08c1990b73388061b115d7332235f3d2d0d755ae1d25a83f4407ad6fa targetHash=0x0b616e141d5d0a4206f2e49ea71243538078665310a613afec5e4aaf138a585a
[2026-05-04 17:52:43] node10 matched log line:
t=05-04|17:52:43.035 lvl=info msg="Parlia finalized block number changed" header=430 prevFinalized=396 newFinalized=428 targetNumber=429 sourceHash=0x0047cf78fe366438f3a32b458bd40a6c78529b5cf47c254d3943800d41fda3fa targetHash=0x000fa3e16f902ec4cb769192186dd7952665fa412357c03bd8aee542b45673c2
```

### For attack 2

The attack is considered successful when both branches finalize independently after the manual split window. The
automation watches multiple branch-local candidate logs:

- A chain: nodes for `412(511)`, `413(bc)`, `414(5a)`, and `415(d2)`.
- B chain: nodes for `411'(50)`, `412'(bb)`, `413'(51)`, `414'(c1)`, and `415'(5e)`.

The terminal should print one `Parlia finalized block number changed` line with `header >= 411` for each branch. The
script then waits until both branches exceed height `450` before stopping the cluster.


## 💻 Source Code

- BSC base (v1.6.6): [https://github.com/bnb-chain/bsc/tree/v1.6.6](https://github.com/bnb-chain/bsc/tree/v1.6.6)
  
  - attack 1 code : ./code/attack-1-code.zip
  - attack 2 code : ./code/attack-2-code.zip
- Node deployment script: [https://github.com/bnb-chain/node-deploy](https://github.com/bnb-chain/node-deploy)

## 📄Appendix

This section outlines the complete manual installation process, including environment setup, dependency installation, and attack execution using raw scripts and source code.

> ⚠️ **Before you begin**, please ensure the following software and system packages are installed on your local machine:

- Ubuntu 20.04/22.04
- nodejs: 18.20.2
- npm: 6.14.6
- go: 1.21+
- python3: 3.12+
- docker: 27.5.1
- foundry: 1.1.0
- poetry: 2.0.0
- jq: 1.7

### Setup steps

1. Unzip and enter the project directory

```bash
unzip node-deploy.zip
cd node-deploy
```

2. Create and activate a virtual environment

```
# Create the virtual environment (if the venv package is not installed)
python3 -m venv path/to/venv

# Create virtual environments
apt install python3.12-venv

# Activate the virtual environment
source path/to/venv/bin/activate
```

3. Install dependencies

```
chmod +x install-dev.sh
sudo ./install-dev.sh
pip3 install -r node-deploy/requirements.txt
```

4. Compile the geth binary

```bash
unzip ./code/attack-1-code.zip
unzip ./code/attack-2-code.zip
unzip ./code/attack-2-turnlen-8-code.zip
unzip ./code/repair-code.zip
unzip ./code/repair-8-code.zip
```

### Launching attack simulation

1. Start attack 1

```bash
cd node-deploy
./test_attack_1_flow.sh
```

2. Start attack 1 with turnlength 8

```bash
cd node-deploy
./test_attack_1_flow.sh --turnlength8
```


The script performs the full attack-1 flow:

- Build the latest `code/attack-1-code` geth binary with `make geth`.
- Build `node-deploy/create-validator` with `go build`.
- Install the geth binary into `node-deploy/bin/geth`.
- Prepare the Python virtual environment and install `node-deploy/requirements.txt`.
- Reset and start the 21-node validator cluster.
- Wait for height `201`, then add Group A validators `21..31` through node0 RPC `8545`.
- Add Group B validators `32..41` through node10 RPC `8555`.
- Wait for height `400`, copy `node11` to `node11-b`, and start the B-side instance with
  `BSC_NETWORK_SPLIT_GROUP=B`.
- Monitor node0 and node10 logs until both print `Parlia finalized block number changed`.
- Stop the cluster with `bash -x ./bsc_cluster_1.sh stop`.

The run is successful when the terminal shows matched finalized-block-change logs for both node0 and node10, as
shown in the [attack success criteria](#for-attack-1).

We recommend running each attack in a clean and isolated environment to ensure independent evaluation. We do not recommend running different attacks in parallel under the same environment.

Please recompile the corresponding binary before running the following attacks.

3. Start attack 2

```bash
cd node-deploy
./test_attack_2_flow.sh
```

4. Start attack 2 with turnlength 8

```bash
cd node-deploy
./test_attack_2_turnlen_8_flow.sh
```

The script performs the full attack-2 flow:

- Build the latest `code/attack-2-code` geth binary with `make geth`.
- Build `node-deploy/create-validator` with `go build`.
- Install the geth binary into `node-deploy/bin/geth`.
- Prepare the Python virtual environment and install `node-deploy/requirements.txt`.
- Reset and start the 21-node validator cluster with `bsc_cluster_2.sh`.
- Wait for height `201`, then start and register A-side extra validators `21..31` through the `398(fe)` node RPC
  (`8553`).
- Start and register B-side extra validators `32..41` through the `398'(5f)` node RPC (`8557`).
- Wait for attack-2 branch-local finalization after height `411`.
- Wait until both branches exceed height `450`, then stop the cluster.


5. Start repair experiment
```bash
cd node-deploy
./repair.sh
```

6. Start repair experiment with turnlength 8
```bash
cd node-deploy
./repair_8.sh
```


## 🐳 Building Docker Images

### Build Prerequisites

### Building Attack 1 Image

### Building Attack 2 Image

### Running Attacks Using Local Docker Images

## Contribution

- For questions or bug reports, please open a GitHub issue in this repository.
