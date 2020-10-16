return {
  -- messages are initially enqueued in the pending table
  function (conn)
    assert(conn:exec[[
      CREATE TABLE "web_pkg_mqueue_pending" (
        "id"              SERIAL NOT NULL,
        "ref_id"          INTEGER NOT NULL,
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" > 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "queue"           VARCHAR(20) NOT NULL,
        "payload"         VARCHAR(1024) NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "web_pkg_mqueue_pending" ("queue", "first_created");
    ]])
  end,

  -- upon dequeuing, they are moved to the active table during processing
  function (conn)
    assert(conn:exec[[
      CREATE TABLE "web_pkg_mqueue_active" (
        "id"              INTEGER NOT NULL CHECK ("id" > 0),
        "ref_id"          INTEGER NOT NULL,
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" > 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "expiry"          INTEGER NOT NULL CHECK ("expiry" > 0),
        "queue"           VARCHAR(20) NOT NULL,
        "payload"         VARCHAR(1024) NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "web_pkg_mqueue_active" ("expiry");
    ]])
  end,

  -- after max attempts, they are moved to the dead table for manual
  -- review and processing.
  function (conn)
    assert(conn:exec[[
      CREATE TABLE "web_pkg_mqueue_dead" (
        "id"              INTEGER NOT NULL CHECK ("id" > 0),
        "ref_id"          INTEGER NOT NULL,
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" > 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "queue"           VARCHAR(20) NOT NULL,
        "payload"         VARCHAR(1024) NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "web_pkg_mqueue_dead" ("queue", "first_created");
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "web_pkg_mqueue_dead" ("created");
    ]])
  end,

  -- a scheduled job moves the messages between active and a) back to
  -- pending or b) dead.
  function (conn)
    assert(conn:exec[[
      CREATE PROCEDURE "web_pkg_mqueue_expire" ()
      AS $$
      BEGIN
        START TRANSACTION;
        -- Note that current_timestamp stays the same for the duration
        -- of the transaction.

        -- move expired messages to the pending table if max_attempts
        -- is not reached.
        INSERT INTO
          "web_pkg_mqueue_pending"
          ("id", "ref_id", "attempts", "max_attempts", "max_age",
           "queue", "payload", "first_created")
        SELECT
          "id",
          "ref_id",
          "attempts",
          "max_attempts",
          "max_age",
          "queue",
          "payload",
          "first_created"
        FROM
          "web_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" < "max_attempts";

        -- delete those messages from the active table
        DELETE FROM
          "web_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" < "max_attempts";

        -- move expired messages with too many attempts to the
        -- dead table.
        INSERT INTO
          "web_pkg_mqueue_dead"
          ("id", "ref_id", "attempts", "max_attempts", "max_age",
           "queue", "payload", "first_created")
        SELECT
          "id",
          "ref_id",
          "attempts",
          "max_attempts",
          "max_age",
          "queue",
          "payload",
          "first_created"
        FROM
          "web_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" >= "max_attempts";

        -- delete those messages from the active table
        DELETE FROM
          "web_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" >= "max_attempts";

        COMMIT;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    -- run the proc every 2 minutes
    assert(conn:query[[
      SELECT
        cron.schedule('web_pkg_mqueue:expire', '*/2 * * * *', 'CALL web_pkg_mqueue_expire()')
    ]])
  end,

  -- a scheduled job removes the dead messages after a while.
  function (conn)
    assert(conn:exec[[
      CREATE PROCEDURE "web_pkg_mqueue_gc" ()
      LANGUAGE SQL
      AS $$
        DELETE FROM
          "web_pkg_mqueue_dead"
        WHERE
          "created" < (current_timestamp - INTERVAL '1 month')
      $$;
    ]])

    -- run the proc every day
    assert(conn:query[[
      SELECT
        cron.schedule('web_pkg_mqueue:gc', '0 2 * * *', 'CALL web_pkg_mqueue_gc()')
    ]])
  end,
}
