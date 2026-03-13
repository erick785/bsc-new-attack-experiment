KEYDIR=/Users/chenxuc/bsc/bsc-attack-experiment/node-deploy/keys
GETH=/path/to/bsc-geth
PASS="0123456789"
for i in $(seq 21 25); do
    # nodekey
    openssl rand -hex 32 > ${KEYDIR}/nodekey${i}
    # validator
    mkdir -p ${KEYDIR}/validator${i}
    echo ${PASS} | ${GETH} account new --datadir ${KEYDIR}/validator${i} --password /dev/stdin
    # bls
    mkdir -p ${KEYDIR}/bls${i}
    echo ${PASS} | ${GETH} bls account new --datadir ${KEYDIR}/bls${i} --blspassword /dev/stdin
done