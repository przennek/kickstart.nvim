-- Live templates ported from IntelliJ (Java.xml, plain.xml, other.xml, surround.xml).
-- Type the abbreviation and accept it from the completion menu (Tab), then Tab through
-- the variables. Surround templates (AE, if, ON, OO): select code in visual mode, press
-- Tab, type the abbreviation and accept it — the selection ends up inside.
local ls = require 'luasnip'
local s, t, i, f = ls.snippet, ls.text_node, ls.insert_node, ls.function_node
local fmt = require('luasnip.extras.fmt').fmt

local function selected()
  return f(function(_, snip)
    local raw = snip.env.LS_SELECT_RAW
    return (raw and #raw > 0) and raw or { '' }
  end)
end

local function test_method(trig, desc)
  return s(
    { trig = trig, desc = desc },
    fmt(
      [[
@Test
public void should{}() {{
    // given
    {}

    // when


    // then


}}]],
      { i(1, 'Name'), i(0) }
    )
  )
end

return {
  -- Java.xml / plain.xml
  s({ trig = 'psf', desc = 'private static final' }, t 'private static final '),
  s({ trig = 'psfs', desc = 'private static final String' }, t 'private static final String '),
  s({ trig = 'pf', desc = 'private final' }, t 'private final '),
  s({ trig = 'nnpfs', desc = '@Nonnull private final String' }, t { '@Nonnull', 'private final String ' }),
  s({ trig = 'nnpfl', desc = '@Nonnull private final Long' }, t { '@Nonnull', 'private final Long ' }),
  s({ trig = 'nnpfd', desc = '@Nonnull private final Double' }, t { '@Nonnull', 'private final Double ' }),
  s(
    { trig = 'tngs', desc = 'TestNG setup method' },
    fmt(
      [[
@BeforeMethod
public void setup() {{
    {}
}}]],
      { i(0) }
    )
  ),
  test_method('tngt', 'TestNG test'),

  -- other.xml (JUnit)
  test_method('jut', 'junit test'),
  s(
    { trig = 'jub', desc = 'junit before' },
    fmt(
      [[
@Before
public void setup() {{
    {}
}}]],
      { i(0) }
    )
  ),
  s({ trig = 'jui', desc = 'junit imports' }, {
    t {
      'import org.junit.After;',
      'import org.junit.Before;',
      'import org.junit.Test;',
      'import org.mockito.Captor;',
      'import org.mockito.Mock;',
      'import org.mockito.Spy;',
      '',
      'import static org.junit.Assert.*;',
      'import static org.mockito.BDDMockito.given;',
      'import static org.mockito.Mockito.verify;',
      '',
    },
    i(0),
  }),
  s({ trig = 'jur', desc = 'MockitoJUnitRunner.Strict' }, {
    t {
      'import org.junit.runner.RunWith;',
      'import org.mockito.junit.MockitoJUnitRunner;',
      '',
      '@RunWith(MockitoJUnitRunner.Strict.class)',
      '',
    },
    i(0),
  }),

  -- surround.xml
  s({ trig = 'AE', desc = 'Surround with assertThat(…).isEqualTo(…)' }, { t 'assertThat(', selected(), t ').isEqualTo(', i(1), t ')', i(0) }),
  s({ trig = 'if', desc = 'Surround with if' }, { t 'if (', selected(), t { ') {', '    ' }, i(0), t { '', '}' } }),
  s({ trig = 'ON', desc = 'Surround with Optional.ofNullable()' }, { t 'Optional.ofNullable(', selected(), t ')', i(0) }),
  s({ trig = 'OO', desc = 'Surround with Optional.of()' }, { t 'Optional.of(', selected(), t ')', i(0) }),
}
