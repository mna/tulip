return {
  function (conn)
    assert(conn:exec[[
      CREATE TABLE "web_pkg_account_sessions" (
        "token"   CHAR(44) NOT NULL,
        "type"    VARCHAR(20) NOT NULL,
        "ref_id"  INTEGER NOT NULL,
        "expiry"  INTEGER NOT NULL CHECK ("expiry" > 0),
        "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("token"),
        UNIQUE ("type", "ref_id")
      )
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "web_pkg_token_tokens" ("expiry");
    ]])
  end,
  [[
    CREATE PROCEDURE "web_pkg_token_expire" ()
    LANGUAGE SQL
    AS $$
      DELETE FROM
        "web_pkg_token_tokens"
      WHERE
        "expiry" < EXTRACT(epoch FROM now())
    $$;
  ]],
  -- schedule expiration of tokens every day at 1AM
  function (conn)
    assert(conn:query[[
      SELECT
        cron.schedule('web_pkg_token:expire', '0 1 * * *', 'CALL web_pkg_token_expire()')
    ]])
  end,
}
