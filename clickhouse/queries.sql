-- 1. Check data volume and date range
SELECT 
    count() as total_rows,
    min(date) as earliest_date,
    max(date) as latest_date,
    round(sum(length(postcode1) + length(postcode2) + length(addr1) + length(addr2) + 
        length(street) + length(locality) + length(town) + length(district) + length(county)) / 1024 / 1024, 2) as approx_size_mb
FROM uk_price_paid;

-- 2. Check partition distribution
SELECT 
    partition,
    count() as rows_per_partition,
    formatReadableSize(sum(bytes_on_disk)) as partition_size
FROM system.parts
WHERE table = 'uk_price_paid' AND active = 1
GROUP BY partition
ORDER BY partition;

-- 3. Check cardinality of key columns (for index decisions)
SELECT 
    uniq(postcode1) as distinct_postcode1,
    uniq(postcode2) as distinct_postcode2,
    uniq(type) as distinct_type,
    uniq(town) as distinct_town,
    uniq(county) as distinct_county
FROM uk_price_paid;
