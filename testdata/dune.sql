-- ============================================================================
-- BSC Validator Set 分析 v2 —— 只统计"真正出块的 21 个共识节点"
--
-- 与 v1 区别：v1 统计的是每天选出的 45 个 active validator（候选池）；
-- v2 只看每个 epoch 真正参与共识出块的 21 个节点。
--
-- "当天的 21 个"口径（用户确认）：
--   取当天 UTC 00:00 之后第一个 epoch 的 21 个实际出块者。
--   实现：bnb.blocks 里 00:00 后的区块，按出块者(miner)首次出块的顺序，
--         取前 21 个不同地址 = 该 epoch 的共识集合（实测每天稳定 = 21）。
--   说明：epoch 长度随硬分叉变化、且一天内会多次轮换（窗口内可见 ~30 个），
--         这里用"首个 epoch"作为当天的代表性快照。
--
-- 质押量：join 当天 updateValidatorSetV2 的 45-set（voting_power），
--         staked_bnb = voting_power / 1e8（= totalPooledBNB）。
--
-- 时间范围：Feynman 硬分叉（mainnet 2024-04-18，首次每日选举 2024-04-19）
--           至 2026 年 4 月底（date < 2026-05-01）。
-- ============================================================================


-- ============================================================================
-- 查询 1：每天真正出块的 21 个共识节点（共识地址 + 质押量），分叉后至 2026-04
-- ============================================================================
WITH blk AS (
    SELECT date AS day, number, miner
    FROM bnb.blocks
    WHERE date >= date '2024-04-18'
      AND date <  date '2026-05-01'
      AND hour(time) = 0 AND minute(time) < 20   -- 00:00 后的窗口，覆盖首个 epoch
),
first_seen AS (
    SELECT day, miner, min(number) AS first_block
    FROM blk
    GROUP BY day, miner
),
-- 按首次出块顺序取前 21 个不同出块者 = 当天首个 epoch 的共识集合
consensus21 AS (
    SELECT day, miner AS validator
    FROM (
        SELECT day, miner,
               row_number() OVER (PARTITION BY day ORDER BY first_block) AS rk
        FROM first_seen
    )
    WHERE rk <= 21
),
-- 当天 45-set 的质押权重（来自 updateValidatorSetV2）
breathe_updates AS (
    SELECT
        block_time AS ts,
        CAST(date_trunc('day', block_time) AS date) AS day,
        "_consensusAddrs" AS validators,
        "_votingPowers"   AS powers
    FROM TABLE(
        decode_evm_function_call(
            abi => '{"name":"updateValidatorSetV2","type":"function","inputs":[{"name":"_consensusAddrs","type":"address[]"},{"name":"_votingPowers","type":"uint64[]"},{"name":"_voteAddrs","type":"bytes[]"}]}',
            data => TABLE(
                SELECT data AS input, CAST(NULL AS varbinary) AS output, block_time
                FROM bnb.transactions
                WHERE "to" = 0x0000000000000000000000000000000000001000
                  AND starts_with(data, 0x1e4c1524)
                  AND success
                  AND block_date >= date '2024-04-18'
                  AND block_date <  date '2026-05-01'
            )
        )
    )
),
daily_pick AS (
    SELECT *, row_number() OVER (PARTITION BY day ORDER BY ts DESC) AS rn
    FROM breathe_updates
),
set45 AS (
    SELECT p.day, t.validator, t.voting_power
    FROM daily_pick p
    CROSS JOIN UNNEST(p.validators, p.powers) AS t(validator, voting_power)
    WHERE p.rn = 1
)
SELECT
    c.day,
    c.validator,                              -- 共识地址（实际出块者）
    s.voting_power,                           -- 原始权重 (uint64)
    s.voting_power / 1e8 AS staked_bnb        -- 质押量 BNB
FROM consensus21 c
LEFT JOIN set45 s ON s.day = c.day AND s.validator = c.validator
ORDER BY c.day DESC, s.voting_power DESC;


-- ============================================================================
-- 查询 2：每周置换率（21 个共识节点，本周 vs 上周），分叉后至 2026-04
-- 取每周最后一个快照日的 21-set 做对比。
-- ============================================================================
WITH blk AS (
    SELECT date AS day, number, miner
    FROM bnb.blocks
    WHERE date >= date '2024-04-18'
      AND date <  date '2026-05-01'
      AND hour(time) = 0 AND minute(time) < 20
),
first_seen AS (
    SELECT day, miner, min(number) AS first_block
    FROM blk GROUP BY day, miner
),
consensus21 AS (
    SELECT day, miner AS validator
    FROM (
        SELECT day, miner,
               row_number() OVER (PARTITION BY day ORDER BY first_block) AS rk
        FROM first_seen
    )
    WHERE rk <= 21
),
week_day AS (
    SELECT day, validator, CAST(date_trunc('week', day) AS date) AS week
    FROM consensus21
),
last_day AS (
    SELECT week, max(day) AS snap_day FROM week_day GROUP BY week
),
weekly_set AS (
    SELECT wd.week, wd.validator
    FROM week_day wd
    JOIN last_day ld ON wd.week = ld.week AND wd.day = ld.snap_day
),
compare AS (
    SELECT
        coalesce(cur.week, prev.week) AS week,
        cur.validator  AS cur_v,
        prev.validator AS prev_v
    FROM weekly_set cur
    FULL OUTER JOIN (
        SELECT week + interval '7' day AS week, validator FROM weekly_set
    ) prev
      ON cur.week = prev.week AND cur.validator = prev.validator
)
SELECT
    week,
    count(*) FILTER (WHERE cur_v  IS NOT NULL)                         AS validators_this_week,
    count(*) FILTER (WHERE prev_v IS NOT NULL)                         AS validators_prev_week,
    count(*) FILTER (WHERE cur_v IS NOT NULL AND prev_v IS NULL)       AS added,
    count(*) FILTER (WHERE cur_v IS NULL AND prev_v IS NOT NULL)       AS removed,
    count(*) FILTER (WHERE cur_v IS NOT NULL AND prev_v IS NOT NULL)   AS stayed,
    CAST(count(*) FILTER (WHERE cur_v IS NULL AND prev_v IS NOT NULL) AS double)
        / NULLIF(count(*) FILTER (WHERE prev_v IS NOT NULL), 0)        AS churn_rate
FROM compare
WHERE week >  (SELECT min(week) FROM weekly_set)
  AND week <= (SELECT max(week) FROM weekly_set)
GROUP BY week
ORDER BY week DESC;


-- ============================================================================
-- 查询 3：质押量 Top 10 随时间变化（仅 21 个共识节点），分叉后至 2026-04
-- 按区间内最后一天(2026-04-30)21-set 中的质押排名取 Top 10，回溯每日质押 BNB。
-- 注意：成员每天可能不同（21 个会轮换），某天不在 21-set 中则无数据点（断线）。
-- ============================================================================
WITH blk AS (
    SELECT date AS day, number, miner
    FROM bnb.blocks
    WHERE date >= date '2024-04-18'
      AND date <  date '2026-05-01'
      AND hour(time) = 0 AND minute(time) < 20
),
first_seen AS (
    SELECT day, miner, min(number) AS first_block
    FROM blk GROUP BY day, miner
),
consensus21 AS (
    SELECT day, miner AS validator
    FROM (
        SELECT day, miner,
               row_number() OVER (PARTITION BY day ORDER BY first_block) AS rk
        FROM first_seen
    )
    WHERE rk <= 21
),
breathe_updates AS (
    SELECT
        block_time AS ts,
        CAST(date_trunc('day', block_time) AS date) AS day,
        "_consensusAddrs" AS validators,
        "_votingPowers"   AS powers
    FROM TABLE(
        decode_evm_function_call(
            abi => '{"name":"updateValidatorSetV2","type":"function","inputs":[{"name":"_consensusAddrs","type":"address[]"},{"name":"_votingPowers","type":"uint64[]"},{"name":"_voteAddrs","type":"bytes[]"}]}',
            data => TABLE(
                SELECT data AS input, CAST(NULL AS varbinary) AS output, block_time
                FROM bnb.transactions
                WHERE "to" = 0x0000000000000000000000000000000000001000
                  AND starts_with(data, 0x1e4c1524)
                  AND success
                  AND block_date >= date '2024-04-18'
                  AND block_date <  date '2026-05-01'
            )
        )
    )
),
daily_pick AS (
    SELECT *, row_number() OVER (PARTITION BY day ORDER BY ts DESC) AS rn
    FROM breathe_updates
),
set45 AS (
    SELECT p.day, t.validator, t.voting_power
    FROM daily_pick p
    CROSS JOIN UNNEST(p.validators, p.powers) AS t(validator, voting_power)
    WHERE p.rn = 1
),
-- 21 个共识节点 + 质押量
consensus_stake AS (
    SELECT c.day, c.validator, s.voting_power, s.voting_power / 1e8 AS staked_bnb
    FROM consensus21 c
    LEFT JOIN set45 s ON s.day = c.day AND s.validator = c.validator
),
latest_top AS (
    SELECT validator
    FROM consensus_stake
    WHERE day = (SELECT max(day) FROM consensus_stake)
    ORDER BY voting_power DESC
    LIMIT 10
)
SELECT
    day,
    concat('0x', lower(to_hex(validator))) AS validator,
    staked_bnb
FROM consensus_stake
WHERE validator IN (SELECT validator FROM latest_top)
ORDER BY day, staked_bnb DESC;
