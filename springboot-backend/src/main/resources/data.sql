
UPDATE user
SET user = 'facker668', pwd = 'cd3911319183fc1815e6f6f53340daa6'
WHERE id = 1
  AND user = 'admin_user'
  AND pwd = '3c85cdebade1c51cf64ca9f3c09d182d'
  AND role_id = 0;

INSERT OR IGNORE INTO user (id, user, pwd, role_id, exp_time, flow, in_flow, out_flow, flow_reset_time, num, created_time, updated_time, status) 
VALUES (1, 'facker668', 'cd3911319183fc1815e6f6f53340daa6', 0, 2727251700000, 99999, 0, 0, 1, 99999, 1748914865000, 1754011744252, 1);


UPDATE vite_config
SET value = '爱转角转发面板'
WHERE name = 'app_name'
  AND value IN ('flux', 'Flux', 'flux-panel');

INSERT OR IGNORE INTO vite_config (id, name, value, time) 
VALUES (1, 'app_name', '爱转角转发面板', 1755147963000);
