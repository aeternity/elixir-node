# This file contains the configuration for Credo and you are probably reading
# this after creating it with `mix credo.gen.config`.
#
# If you find anything wrong or unclear in this file, please report an
# issue on GitHub: https://github.com/rrrene/credo/issues
#
%{
  #
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      #
      # Run any exec using `mix credo -C <name>`. If no exec name is given
      # "default" is used.
      #
      name: "default",
      #
      # These are the files included in the analysis:
      files: %{
        #
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        #
        included: ["lib/", "src/", "web/", "apps/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      requires: [],
      #
      # If you want to enforce a style guide and need a more traditional linting
      # experience, you can change `strict` to `true` below:
      #
      strict: true,
      #
      # If you want to use uncolored output by default, you can change `color`
      # to `false` below:
      #
      color: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #
      #
      checks: [
        {Credo.Check.Consistency.ExceptionNames},
        {Credo.Check.Consistency.LineEndings},
        {Credo.Check.Consistency.ParameterPatternMatching},
        {Credo.Check.Consistency.SpaceAroundOperators},
        {Credo.Check.Consistency.SpaceInParentheses},
        {Credo.Check.Consistency.TabsOrSpaces},

        # You can customize the priority of any check
        # Priority values are: `low, normal, high, higher`
        #
        {Credo.Check.Design.AliasUsage, priority: :normal},

        # For some checks, you can also set other parameters
        #
        # If you don't want the `setup` and `test` macro calls in ExUnit tests
        # or the `schema` macro in Ecto schemas to trigger DuplicatedCode, just
        # set the `excluded_macros` parameter to `[:schema, :setup, :test]`.
        #
        {Credo.Check.Design.DuplicatedCode, false},

        # You can also customize the exit_status of each check.
        # If you don't want TODO comments to cause `mix credo` to fail, just
        # set this value to 0 (zero).
        #
        {Credo.Check.Design.TagTODO, exit_status: 2},
        {Credo.Check.Design.TagFIXME, exit_status: 0},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Readability.FunctionNames, priority: :higher},
        {Credo.Check.Readability.LargeNumbers, priority: :high},
        {Credo.Check.Readability.MaxLineLength, false},
        {Credo.Check.Readability.ModuleAttributeNames, priority: :higher},
        {Credo.Check.Readability.ModuleDoc, priority: :higher},
        {Credo.Check.Readability.ModuleNames, priority: :higher},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, priority: :higher},
        {Credo.Check.Readability.ParenthesesInCondition, priority: :higher},
        {Credo.Check.Readability.PredicateFunctionNames, priority: :higher},
        {Credo.Check.Readability.PreferImplicitTry, exit_status: 0},
        {Credo.Check.Readability.RedundantBlankLines, priority: :higher},
        {Credo.Check.Readability.StringSigils, exit_status: 0},
        {Credo.Check.Readability.TrailingBlankLine, priority: :higher},
        {Credo.Check.Readability.TrailingWhiteSpace, priority: :higher},
        {Credo.Check.Readability.VariableNames, priority: :higher},
        {Credo.Check.Readability.Semicolons, priority: :higher},
        {Credo.Check.Readability.SpaceAfterCommas, priority: :higher},
        {Credo.Check.Refactor.DoubleBooleanNegation, exit_status: 0},
        {Credo.Check.Refactor.CondStatements, priority: :higher},
        {Credo.Check.Refactor.CyclomaticComplexity, exit_status: 0, max_complexity: 20},
        {Credo.Check.Refactor.FunctionArity, exit_status: 0, max_arity: 10},
        {Credo.Check.Refactor.LongQuoteBlocks, exit_status: 0},
        {Credo.Check.Refactor.MatchInCondition, priority: :higher},
        {Credo.Check.Refactor.NegatedConditionsInUnless, priority: :high},
        {Credo.Check.Refactor.NegatedConditionsWithElse, priority: :high},
        {Credo.Check.Refactor.Nesting, priority: :high, max_nesting: 3},
        {Credo.Check.Refactor.PipeChainStart, priority: :higher},
        {Credo.Check.Refactor.UnlessWithElse, priority: :higher},
        {Credo.Check.Warning.BoolOperationOnSameValues, priority: :higher},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, priority: :higher},
        {Credo.Check.Warning.IExPry, priority: :higher},
        {Credo.Check.Warning.IoInspect, priority: :higher},
        {Credo.Check.Warning.LazyLogging, priority: :high},
        {Credo.Check.Warning.OperationOnSameValues, exit_status: 0},
        {Credo.Check.Warning.OperationWithConstantResult, exit_status: 0},
        {Credo.Check.Warning.UnusedEnumOperation, priority: :high},
        {Credo.Check.Warning.UnusedFileOperation, priority: :high},
        {Credo.Check.Warning.UnusedKeywordOperation, priority: :high},
        {Credo.Check.Warning.UnusedListOperation, priority: :high},
        {Credo.Check.Warning.UnusedPathOperation, priority: :high},
        {Credo.Check.Warning.UnusedRegexOperation, priority: :high},
        {Credo.Check.Warning.UnusedStringOperation, priority: :high},
        {Credo.Check.Warning.UnusedTupleOperation, priority: :high},
        {Credo.Check.Warning.RaiseInsideRescue, priority: :high},

        # Controversial and experimental checks (opt-in, just remove `, false`)
        #
        # {Credo.Check.Refactor.ABCSize},
        {Credo.Check.Refactor.AppendSingleItem, priority: :high},
        {Credo.Check.Refactor.VariableRebinding, exit_status: 0},
        {Credo.Check.Warning.MapGetUnsafePass, exit_status: 0},
        {Credo.Check.Consistency.MultiAliasImportRequireUse, false},

        # Deprecated checks (these will be deleted after a grace period)
        #
        {Credo.Check.Readability.Specs, false}

        # Custom checks can be created using `mix credo.gen.check`.
        #
      ]
    }
  ]
}
