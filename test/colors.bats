#!/usr/bin/env bats
# Tests for lib/colors.sh

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# --- setup_colors with NO_COLOR ---

@test "setup_colors: sets empty color vars when NO_COLOR is set" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$GREEN" ""
  assert_equal "$RED" ""
  assert_equal "$NC" ""
}

@test "setup_colors: GREEN is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$GREEN" ""
}

@test "setup_colors: RED is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$RED" ""
}

@test "setup_colors: YELLOW is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$YELLOW" ""
}

@test "setup_colors: BLUE is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$BLUE" ""
}

@test "setup_colors: MAGENTA is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$MAGENTA" ""
}

@test "setup_colors: CYAN is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$CYAN" ""
}

@test "setup_colors: WHITE is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$WHITE" ""
}

@test "setup_colors: DIM is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$DIM" ""
}

@test "setup_colors: BOLD is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$BOLD" ""
}

@test "setup_colors: UNDERLINE is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$UNDERLINE" ""
}

@test "setup_colors: ORANGE is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$ORANGE" ""
}

@test "setup_colors: NC is empty when NO_COLOR is exported" {
  export NO_COLOR=1
  setup_colors
  assert_equal "$NC" ""
}

# --- All expected color variable names are defined ---

@test "setup_colors: all expected color variable names are defined after setup_colors" {
  export NO_COLOR=1
  setup_colors
  # All variables should be defined (even if empty) - test with declare -p
  local vars=(GREEN YELLOW BLUE RED MAGENTA CYAN WHITE ORANGE DIM BOLD UNDERLINE NC)
  for var in "${vars[@]}"; do
    declare -p "$var" >/dev/null 2>&1
  done
}
