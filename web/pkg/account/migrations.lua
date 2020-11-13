return {
  [[
    CREATE TABLE "web_pkg_account_accounts" (
      "id"       SERIAL NOT NULL,
      -- see https://stackoverflow.com/a/574698/1094941
      "email"    VARCHAR(254) NOT NULL,
      "password" VARCHAR(200) NOT NULL,
      "verified" TIMESTAMPTZ NULL,
      "created"  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("id"),
      UNIQUE ("email")
    )
  ]],
  [[
    CREATE TABLE "web_pkg_account_groups" (
      "id"       SERIAL NOT NULL,
      "name"     VARCHAR(20) NOT NULL,
      "created"  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("id"),
      UNIQUE ("name")
    )
  ]],
  [[
    CREATE TABLE "web_pkg_account_members" (
      "id"         SERIAL NOT NULL,
      "account_id" INTEGER NOT NULL,
      "group_id"   INTEGER NOT NULL,
      "created"    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("id"),
      FOREIGN KEY ("account_id")
        REFERENCES "web_pkg_account_accounts" ("id"),
      FOREIGN KEY ("group_id")
        REFERENCES "web_pkg_account_groups" ("id")
    )
  ]],
}
