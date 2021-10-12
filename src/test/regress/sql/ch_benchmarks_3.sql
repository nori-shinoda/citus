SET search_path to "ch benchmarks";

-- Subquery + repartion is supported when it is an IN query where the subquery
-- returns unique results (because it's converted to an INNER JOIN)
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_id from item)
        AND s_i_id = ol_i_id
    order by s_i_id;

select   su_name, su_address
from     supplier, nation
where    su_suppkey in
        (select  mod(s_i_id * s_w_id, 10000)
        from     stock, order_line
        where    s_i_id in
                (select i_id
                 from item
                 where i_data like 'ab%')
             and ol_i_id=s_i_id
             and ol_delivery_d > '2010-05-23 12:00:00'
        group by s_i_id, s_w_id, s_quantity
        having   2*s_quantity > sum(ol_quantity))
     and su_nationkey = n_nationkey
     and n_name = 'Germany'
order by su_name;
