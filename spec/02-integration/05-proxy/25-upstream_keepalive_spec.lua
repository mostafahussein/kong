local helpers = require "spec.helpers"


describe("upstream keepalive", function()
  local proxy_client

  local function start_kong(opts)
    local kopts = {
      log_level  = "debug",
      database   = "postgres",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }

    for k, v in pairs(opts or {}) do
      kopts[k] = v
    end

    -- cleanup logs
    os.execute(":> " .. helpers.test_conf.nginx_err_logs)

    assert(helpers.start_kong(kopts))

    proxy_client = helpers.proxy_client()
  end

  lazy_setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "routes",
      "services",
    })

    bp.routes:insert {
      hosts = { "one.com" },
      preserve_host = true,
      service = bp.services:insert {
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      },
    }

    bp.routes:insert {
      hosts = { "two.com" },
      preserve_host = true,
      service = bp.services:insert {
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      },
    }
  end)


  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong(nil, true)
  end)


  it("pool by host|port|sni when upstream is https", function()
    start_kong()

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "one.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=one.com", body)
    assert.errlog()
          .has
          .line([[enabled connection keepalive \(pool=[A-F0-9.:]+\|\d+\|one.com]])

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "two.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=two.com", body)
    assert.errlog()
          .has
          .line([[enabled connection keepalive \(pool=[A-F0-9.:]+\|\d+\|two.com]])
  end)


  it("upstream_keepalive_pool_size = 0 disables connection pooling", function()
    start_kong({
      upstream_keepalive_pool_size = 0,
    })

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "one.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=one.com", body)
    assert.errlog()
          .not_has
          .line("enabled connection keepalive", true)

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "two.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=two.com", body)
    assert.errlog()
          .not_has
          .line("enabled connection keepalive", true)
  end)


  describe("deprecated properties", function()
    it("nginx_upstream_keepalive = NONE disables connection pooling", function()
      start_kong({
        nginx_upstream_keepalive = "NONE",
      })

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/echo_sni",
        headers = {
          Host = "one.com",
        }
      })
      local body = assert.res_status(200, res)
      assert.equal("SNI=one.com", body)
      assert.errlog()
            .not_has
            .line("enabled connection keepalive", true)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/echo_sni",
        headers = {
          Host = "two.com",
        }
      })
      local body = assert.res_status(200, res)
      assert.equal("SNI=two.com", body)
      assert.errlog()
            .not_has
            .line("enabled connection keepalive", true)
    end)
  end)
end)
