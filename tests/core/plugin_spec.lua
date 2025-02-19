local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")

local assert = require("luassert")

Config.setup()

describe("plugin spec url/name", function()
  local tests = {
    { { dir = "~/foo" }, { name = "foo", dir = vim.fn.fnamemodify("~/foo", ":p") } },
    { { dir = "/tmp/foo" }, { dir = "/tmp/foo", name = "foo" } },
    { { "foo/bar" }, { [1] = "foo/bar", name = "bar", url = "https://github.com/foo/bar.git" } },
    { { "foo/bar", name = "foobar" }, { [1] = "foo/bar", name = "foobar", url = "https://github.com/foo/bar.git" } },
    { { "foo/bar", url = "123" }, { [1] = "foo/bar", name = "123", url = "123" } },
    { { url = "https://foobar" }, { name = "foobar", url = "https://foobar" } },
    { { url = "ssh://foobar" }, { name = "foobar", url = "ssh://foobar" } },
    { "foo/bar", { [1] = "foo/bar", name = "bar", url = "https://github.com/foo/bar.git" } },
    { { { { "foo/bar" } } }, { [1] = "foo/bar", name = "bar", url = "https://github.com/foo/bar.git" } },
  }

  for _, test in ipairs(tests) do
    test[2]._ = {}
    it("parses " .. vim.inspect(test[1]):gsub("%s+", " "), function()
      if not test[2].dir then
        test[2].dir = Config.options.root .. "/" .. test[2].name
      end
      local spec = Plugin.Spec.new(test[1])
      local plugins = vim.tbl_values(spec.plugins)
      assert(#spec.errors == 0)
      assert.equal(1, #plugins)
      assert.same(test[2], plugins[1])
    end)
  end
end)

describe("plugin spec opt", function()
  it("handles dependencies", function()
    Config.options.defaults.lazy = false
    local tests = {
      { "foo/bar", dependencies = { "foo/dep1", "foo/dep2" } },
      { "foo/bar", dependencies = { { "foo/dep1" }, "foo/dep2" } },
      { { { "foo/bar", dependencies = { { "foo/dep1" }, "foo/dep2" } } } },
    }
    for _, test in ipairs(tests) do
      local spec = Plugin.Spec.new(vim.deepcopy(test))
      assert(#spec.errors == 0)
      Config.plugins = spec.plugins
      Plugin.update_state()
      assert(vim.tbl_count(spec.plugins) == 3)
      assert(#spec.plugins.bar.dependencies == 2)
      assert(spec.plugins.bar._.dep ~= true)
      assert(spec.plugins.bar.lazy == false)
      assert(spec.plugins.dep1._.dep == true)
      assert(spec.plugins.dep1.lazy == true)
      assert(spec.plugins.dep2._.dep == true)
      assert(spec.plugins.dep2.lazy == true)
      spec = Plugin.Spec.new(test)
      for _, plugin in pairs(spec.plugins) do
        plugin.dir = nil
      end
      assert.same(spec.plugins, {
        bar = {
          "foo/bar",
          _ = {},
          dependencies = { "dep1", "dep2" },
          name = "bar",
          url = "https://github.com/foo/bar.git",
        },
        dep1 = {
          "foo/dep1",
          _ = {
            dep = true,
          },
          name = "dep1",
          url = "https://github.com/foo/dep1.git",
        },
        dep2 = {
          "foo/dep2",
          _ = {
            dep = true,
          },
          name = "dep2",
          url = "https://github.com/foo/dep2.git",
        },
      })
    end
  end)

  describe("deps", function()
    it("handles dep names", function()
      Config.options.defaults.lazy = false
      local tests = {
        { { "foo/bar", dependencies = { { "dep1" }, "foo/dep2" } }, "foo/dep1" },
        { "foo/dep1", { "foo/bar", dependencies = { { "dep1" }, "foo/dep2" } } },
      }
      for _, test in ipairs(tests) do
        local spec = Plugin.Spec.new(vim.deepcopy(test))
        assert(#spec.errors == 0)
        Config.plugins = spec.plugins
        Plugin.update_state()
        spec = Plugin.Spec.new(test)
        for _, plugin in pairs(spec.plugins) do
          plugin.dir = nil
        end
        assert.same(spec.plugins, {
          bar = {
            "foo/bar",
            _ = {},
            dependencies = { "dep1", "dep2" },
            name = "bar",
            url = "https://github.com/foo/bar.git",
          },
          dep1 = {
            "foo/dep1",
            _ = {},
            name = "dep1",
            url = "https://github.com/foo/dep1.git",
          },
          dep2 = {
            "foo/dep2",
            _ = {
              dep = true,
            },
            name = "dep2",
            url = "https://github.com/foo/dep2.git",
          },
        })
      end
    end)

    it("handles opt from dep", function()
      Config.options.defaults.lazy = false
      local spec = Plugin.Spec.new({ "foo/dep1", { "foo/bar", dependencies = { "foo/dep1", "foo/dep2" } } })
      assert(#spec.errors == 0)
      Config.plugins = spec.plugins
      Plugin.update_state()
      assert.same(3, vim.tbl_count(spec.plugins))
      assert(spec.plugins.bar._.dep ~= true)
      assert(spec.plugins.bar.lazy == false)
      assert(spec.plugins.dep2._.dep == true)
      assert(spec.plugins.dep2.lazy == true)
      assert(spec.plugins.dep1._.dep ~= true)
      assert(spec.plugins.dep1.lazy == false)
    end)

    it("handles defaults opt", function()
      do
        Config.options.defaults.lazy = true
        local spec = Plugin.Spec.new({ "foo/bar" })
        assert(#spec.errors == 0)
        Config.plugins = spec.plugins
        Plugin.update_state()
        assert(spec.plugins.bar.lazy == true)
      end
      do
        Config.options.defaults.lazy = false
        local spec = Plugin.Spec.new({ "foo/bar" })
        Config.plugins = spec.plugins
        Plugin.update_state()
        assert(spec.plugins.bar.lazy == false)
      end
    end)

    it("handles opt from dep", function()
      Config.options.defaults.lazy = false
      local spec = Plugin.Spec.new({ "foo/bar", event = "foo" })
      assert(#spec.errors == 0)
      Config.plugins = spec.plugins
      Plugin.update_state()
      assert.same(1, vim.tbl_count(spec.plugins))
      assert(spec.plugins.bar._.dep ~= true)
      assert(spec.plugins.bar.lazy == true)
    end)

    it("merges lazy loaders", function()
      local tests = {
        { { "foo/bar", event = "mod1" }, { "foo/bar", event = "mod2" } },
        { { "foo/bar", event = { "mod1" } }, { "foo/bar", event = { "mod2" } } },
        { { "foo/bar", event = "mod1" }, { "foo/bar", event = { "mod2" } } },
      }
      for _, test in ipairs(tests) do
        local spec = Plugin.Spec.new(test)
        assert(#spec.errors == 0)
        assert(vim.tbl_count(spec.plugins) == 1)
        assert(type(spec.plugins.bar.event) == "table")
        assert(#spec.plugins.bar.event == 2)
        assert(vim.tbl_contains(spec.plugins.bar.event, "mod1"))
        assert(vim.tbl_contains(spec.plugins.bar.event, "mod2"))
      end
    end)

    it("refuses to merge", function()
      local spec = Plugin.Spec.new({
        { "foo/dep1", config = 1 },
        {
          "foo/bar",
          dependencies = { { "foo/dep1", config = 2 }, "foo/dep2" },
        },
      })
      assert(#spec.errors > 0)
    end)

    -- it("recursive deps", function()
    --   local spec = Plugin.Spec.new({
    --     "nvim-telescope/telescope.nvim",
    --     dependencies = {
    --       "nvim-lua/plenary.nvim",
    --       { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    --       { "nvim-telescope/telescope-frecency.nvim", dependencies = "kkharji/sqlite.lua" },
    --     },
    --   })
    -- end)
  end)

  it("handles opt from dep", function()
    Config.options.defaults.lazy = false
    local spec = Plugin.Spec.new({ "foo/dep1", { "foo/bar", dependencies = { "foo/dep1", "foo/dep2" } } })
    assert(#spec.errors == 0)
    Config.plugins = spec.plugins
    Plugin.update_state()
    assert.same(3, vim.tbl_count(spec.plugins))
    assert(spec.plugins.bar._.dep ~= true)
    assert(spec.plugins.bar.lazy == false)
    assert(spec.plugins.dep2._.dep == true)
    assert(spec.plugins.dep2.lazy == true)
    assert(spec.plugins.dep1._.dep ~= true)
    assert(spec.plugins.dep1.lazy == false)
  end)

  it("handles defaults opt", function()
    do
      Config.options.defaults.lazy = true
      local spec = Plugin.Spec.new({ "foo/bar" })
      assert(#spec.errors == 0)
      Config.plugins = spec.plugins
      Plugin.update_state()
      assert(spec.plugins.bar.lazy == true)
    end
    do
      Config.options.defaults.lazy = false
      local spec = Plugin.Spec.new({ "foo/bar" })
      Config.plugins = spec.plugins
      Plugin.update_state()
      assert(spec.plugins.bar.lazy == false)
    end
  end)

  it("handles opt from dep", function()
    Config.options.defaults.lazy = false
    local spec = Plugin.Spec.new({ "foo/bar", event = "foo" })
    assert(#spec.errors == 0)
    Config.plugins = spec.plugins
    Plugin.update_state()
    assert.same(1, vim.tbl_count(spec.plugins))
    assert(spec.plugins.bar._.dep ~= true)
    assert(spec.plugins.bar.lazy == true)
  end)

  it("merges lazy loaders", function()
    local tests = {
      { { "foo/bar", event = "mod1" }, { "foo/bar", event = "mod2" } },
      { { "foo/bar", event = { "mod1" } }, { "foo/bar", event = { "mod2" } } },
      { { "foo/bar", event = "mod1" }, { "foo/bar", event = { "mod2" } } },
    }
    for _, test in ipairs(tests) do
      local spec = Plugin.Spec.new(test)
      assert(#spec.errors == 0)
      assert(vim.tbl_count(spec.plugins) == 1)
      assert(type(spec.plugins.bar.event) == "table")
      assert(#spec.plugins.bar.event == 2)
      assert(vim.tbl_contains(spec.plugins.bar.event, "mod1"))
      assert(vim.tbl_contains(spec.plugins.bar.event, "mod2"))
    end
  end)

  it("refuses to merge", function()
    local spec = Plugin.Spec.new({
      { "foo/dep1", config = 1 },
      {
        "foo/bar",
        dependencies = { { "foo/dep1", config = 2 }, "foo/dep2" },
      },
    })
    assert(#spec.errors > 0)
  end)

  -- it("recursive deps", function()
  --   local spec = Plugin.Spec.new({
  --     "nvim-telescope/telescope.nvim",
  --     dependencies = {
  --       "nvim-lua/plenary.nvim",
  --       { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  --       { "nvim-telescope/telescope-frecency.nvim", dependencies = "kkharji/sqlite.lua" },
  --     },
  --   })
  -- end)
end)
