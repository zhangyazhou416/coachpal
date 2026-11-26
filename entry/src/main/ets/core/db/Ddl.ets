/// 本地 SQLite DDL：与 drift schema v1 逐列一致（同步兼容红线，勿改列名/类型）。

export const DDL_STATEMENTS: string[] = [
  `CREATE TABLE IF NOT EXISTS profile (
    id INTEGER NOT NULL PRIMARY KEY,
    sex TEXT NOT NULL DEFAULT 'male',
    birth_date TEXT,
    height_cm REAL,
    activity_level TEXT NOT NULL DEFAULT 'moderate',
    goal_type TEXT NOT NULL DEFAULT 'maintain',
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS body_metrics (
    uuid TEXT NOT NULL PRIMARY KEY,
    date TEXT NOT NULL UNIQUE,
    weight_kg REAL,
    body_fat_pct REAL,
    skeletal_muscle_kg REAL,
    note TEXT,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS measurements (
    uuid TEXT NOT NULL PRIMARY KEY,
    date TEXT NOT NULL,
    site TEXT NOT NULL,
    value_cm REAL NOT NULL,
    note TEXT,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    UNIQUE (date, site)
  )`,
  `CREATE TABLE IF NOT EXISTS goals (
    uuid TEXT NOT NULL PRIMARY KEY,
    kind TEXT NOT NULL,
    target_value REAL NOT NULL,
    unit TEXT,
    baseline_value REAL,
    target_date TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS strength_logs (
    uuid TEXT NOT NULL PRIMARY KEY,
    date TEXT NOT NULL,
    lift TEXT NOT NULL,
    weight_kg REAL NOT NULL,
    reps INTEGER NOT NULL,
    rpe REAL,
    estimated_1rm REAL NOT NULL,
    note TEXT,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS meals (
    uuid TEXT NOT NULL PRIMARY KEY,
    date TEXT NOT NULL,
    meal_type TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS meal_items (
    uuid TEXT NOT NULL PRIMARY KEY,
    meal_uuid TEXT NOT NULL,
    food_id INTEGER,
    food_name TEXT NOT NULL,
    grams REAL NOT NULL,
    kcal REAL NOT NULL,
    protein REAL NOT NULL,
    fat REAL NOT NULL,
    carbs REAL NOT NULL,
    fiber REAL,
    source TEXT NOT NULL DEFAULT 'db',
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS workouts (
    uuid TEXT NOT NULL PRIMARY KEY,
    date TEXT NOT NULL,
    name TEXT,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS workout_sets (
    uuid TEXT NOT NULL PRIMARY KEY,
    workout_uuid TEXT NOT NULL,
    exercise_id INTEGER,
    exercise_name TEXT NOT NULL,
    set_no INTEGER,
    weight_kg REAL,
    reps INTEGER,
    rpe REAL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )`,
  // 参考数据（不同步）
  `CREATE TABLE IF NOT EXISTS foods (
    name TEXT NOT NULL PRIMARY KEY,
    code TEXT,
    name_en TEXT,
    category TEXT,
    kcal REAL,
    protein REAL,
    fat REAL,
    carbs REAL,
    fiber REAL,
    gi REAL
  )`,
  `CREATE TABLE IF NOT EXISTS exercises (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    cat TEXT,
    equip TEXT,
    target TEXT,
    secondary TEXT,
    steps_en TEXT,
    steps_zh TEXT,
    gif_path TEXT,
    thumb_path TEXT
  )`,
  // 同步游标
  `CREATE TABLE IF NOT EXISTS sync_state (
    table_ TEXT NOT NULL PRIMARY KEY,
    last_pull TEXT NOT NULL
  )`,
];

/** 每次开库兜底：档案行缺失则补（OR IGNORE 不覆盖已有数据）。 */
export const PROFILE_FALLBACK_SQL: string =
  `INSERT OR IGNORE INTO profile (id, sex, activity_level, goal_type, updated_at) ` +
  `VALUES (1, 'male', 'moderate', 'maintain', ?)`;
