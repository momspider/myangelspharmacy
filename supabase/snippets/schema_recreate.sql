-- 1. Drop the schema and everything inside it
DROP SCHEMA public CASCADE;

-- 2. Recreate the clean schema
CREATE SCHEMA public;

-- 3. Restore standard privileges so extensions and roles work properly
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
