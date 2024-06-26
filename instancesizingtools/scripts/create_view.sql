CREATE OR REPLACE VIEW "v_instance_sizing" AS 
SELECT
  database_name
, instance_type_aws aws_instance_type
, cpu_prem_count cpu_onprem_utilization_count
, cpu_aws_count cpu_aws_capacity_count
, memory_prem_gb memory_onprem_utilization_gb
, memory_aws_gb memory_aws_capacity_gb
, bandwidth_prem_mbps bandwidth_onprem_utilization_mbps
, bandwidth_aws_mbps bandwidth_aws_capacity_mbps
, db_size_gb
FROM
  (
   SELECT
     replace(database_name, '"', '') database_name
   , memory_prem_gb
   , i.memory memory_aws_gb
   , (i.memory - memory_prem_gb) mem_diff
   , cpu_prem_count
   , i.vcpu cpu_aws_count
   , (i.vcpu - cpu_prem_count) cpu_diff
   , bandwidth_prem_mbps
   , i.bandwidth bandwidth_aws_mbps
   , (i.bandwidth - d.bandwidth_prem_mbps) bandwith_diff
   , db_size_gb
   , i.instance_type instance_type_aws
   , rank() OVER (PARTITION BY database_name ORDER BY (i.vcpu - cpu_prem_count) ASC, (i.memory - memory_prem_gb) ASC, (i.bandwidth - bandwidth_prem_mbps) ASC) rnk
   FROM
     (
      SELECT
        p.database_name
      , round((sum((((cpunumber * cpupct) / 1E2) / cpu_weight)) * 1.2E0), 2) cpu_prem_count
      , round((sum((db_memory_mb / 1.024E3)) * 1.2E0), 2) memory_prem_gb
      , round(max(((db_sizeusage_mb / 1.024E3) * 1.2E0)), 2) db_size_gb
      , round((sum(db_bandwidth_prem_mbps) * 1.2E0), 0) bandwidth_prem_mbps
      FROM
        (
         SELECT
           database_name
         , host_name
         , cpunumber
         , db_sizeusage_mb
         , hostcpupctmax_hourly cpupct
         , db_memory_mb
         FROM
           (
            SELECT
              database_name
            , host_name
            , hostcpupctmax_hourly
            , (CASE cpunumber WHEN 0 THEN 1 ELSE cpunumber END) cpunumber
            , row_number() OVER (PARTITION BY database_name, host_name ORDER BY (hostcpupctmax_hourly * (CASE cpunumber WHEN 0 THEN 1 ELSE cpunumber END)) DESC) rn
            , count(*) OVER (PARTITION BY database_name, host_name) cnt
            , max((sgamb + pgamb)) OVER (PARTITION BY database_name, host_name) db_memory_mb
            , tbsizeusedmb db_sizeusage_mb
            FROM
              perforacle
         ) 
         WHERE (rn = round((cnt * 1E-1), 0))
      )  p
      , (
         SELECT
           database_name
         , host_name
         , db_bandwidth_prem_mbps
         FROM
           (
            SELECT
              database_name
            , host_name
            , ((((rdbtpsavg_hourly + wtbtpsavg_hourly) * 8) / 1024) / 1024) db_bandwidth_prem_mbps
            , row_number() OVER (PARTITION BY database_name, host_name ORDER BY (rdbtpsavg_hourly + wtbtpsavg_hourly) DESC) rn
            , count(*) OVER (PARTITION BY database_name, host_name) cnt
            FROM
              perforacle
         ) 
         WHERE (rn = round((cnt * 1E-1), 0))
      )  s
      , (
         SELECT
           host_name
         , count(DISTINCT database_name) cpu_weight
         FROM
           perforacle
         GROUP BY host_name
      )  h
      WHERE (((p.database_name = s.database_name) AND (p.host_name = s.host_name)) AND (p.host_name = h.host_name))
      GROUP BY p.database_name
   )  d
   , instancelookup i
   WHERE (((i.memory - d.memory_prem_gb) >= 0) AND ((i.vcpu - cpu_prem_count) >= 0) AND ((i.bandwidth - bandwidth_prem_mbps) >= 0))
) 
WHERE (rnk = 1)
ORDER BY database_name ASC
