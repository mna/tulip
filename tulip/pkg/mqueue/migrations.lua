local xerror = require 'tulip.xerror'

return {
  -- messages are initially enqueued in the pending table
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE TABLE "tulip_pkg_mqueue_pending" (
        "id"              SERIAL NOT NULL,
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" >= 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "queue"           VARCHAR(100) NOT NULL,
        "payload"         JSONB NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_mqueue_pending" ("queue", "first_created");
    ]]))
  end,

  -- upon dequeuing, they are moved to the active table during processing
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE TABLE "tulip_pkg_mqueue_active" (
        "id"              INTEGER NOT NULL CHECK ("id" > 0),
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" > 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "expiry"          BIGINT NOT NULL CHECK ("expiry" > 0),
        "queue"           VARCHAR(100) NOT NULL,
        "payload"         JSONB NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_mqueue_active" ("expiry");
    ]]))
  end,

  -- after max attempts, they are moved to the dead table for manual
  -- review and processing.
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE TABLE "tulip_pkg_mqueue_dead" (
        "id"              INTEGER NOT NULL CHECK ("id" > 0),
        "attempts"        SMALLINT NOT NULL CHECK ("attempts" > 0),
        "max_attempts"    SMALLINT NOT NULL CHECK ("max_attempts" > 0),
        "max_age"         INTEGER NOT NULL CHECK ("max_age" > 0),
        "queue"           VARCHAR(100) NOT NULL,
        "payload"         JSONB NOT NULL,
        "first_created"   TIMESTAMPTZ NOT NULL,
        "created"         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_mqueue_dead" ("queue", "first_created");
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_mqueue_dead" ("created");
    ]]))
  end,

  -- a scheduled job moves the messages between active and a) back to
  -- pending or b) dead.
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE PROCEDURE "tulip_pkg_mqueue_expire" ()
      AS $$
      BEGIN
        -- Note that current_timestamp stays the same for the duration
        -- of the transaction.

        -- move expired messages to the pending table if max_attempts
        -- is not reached.
        INSERT INTO
          "tulip_pkg_mqueue_pending"
          ("id", "attempts", "max_attempts", "max_age",
           "queue", "payload", "first_created")
        SELECT
          "id",
          "attempts",
          "max_attempts",
          "max_age",
          "queue",
          "payload",
          "first_created"
        FROM
          "tulip_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" < "max_attempts";

        -- delete those messages from the active table
        DELETE FROM
          "tulip_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" < "max_attempts";

        -- move expired messages with too many attempts to the
        -- dead table.
        INSERT INTO
          "tulip_pkg_mqueue_dead"
          ("id", "attempts", "max_attempts", "max_age",
           "queue", "payload", "first_created")
        SELECT
          "id",
          "attempts",
          "max_attempts",
          "max_age",
          "queue",
          "payload",
          "first_created"
        FROM
          "tulip_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" >= "max_attempts";

        -- delete those messages from the active table
        DELETE FROM
          "tulip_pkg_mqueue_active"
        WHERE
          "expiry" < EXTRACT(epoch FROM current_timestamp) AND
          "attempts" >= "max_attempts";

        COMMIT;
      END;
      $$ LANGUAGE plpgsql;
    ]]))

    -- run the proc every 2 minutes
    xerror.must(xerror.db(conn:query[[
      SELECT
        cron.schedule('tulip_pkg_mqueue:expire', '*/2 * * * *', 'CALL tulip_pkg_mqueue_expire()')
    ]]))
  end,

  -- a scheduled job removes the dead messages after a while.
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE PROCEDURE "tulip_pkg_mqueue_gc" ()
      LANGUAGE SQL
      AS $$
        DELETE FROM
          "tulip_pkg_mqueue_dead"
        WHERE
          "created" < (current_timestamp - INTERVAL '1 month')
      $$;
    ]]))

    -- run the proc every day
    xerror.must(xerror.db(conn:query[[
      SELECT
        cron.schedule('tulip_pkg_mqueue:gc', '0 2 * * *', 'CALL tulip_pkg_mqueue_gc()')
    ]]))
  end,

  -- a function to enqueue a message
  [[
    CREATE FUNCTION "tulip_pkg_mqueue_enqueue"
      (queue TEXT, max_att SMALLINT, max_age INTEGER, payload TEXT)
      RETURNS INTEGER
    LANGUAGE SQL
    AS $$
      INSERT INTO
        "tulip_pkg_mqueue_pending"
        ("attempts", "max_attempts", "max_age", "queue", "payload")
      VALUES
        (0, max_att, max_age, queue, payload::jsonb)
      RETURNING
        "id"
    $$;
  ]],
}
