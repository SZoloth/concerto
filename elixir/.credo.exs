%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      color: true,
      checks: %{
        disabled: [
          # TODO tags are intentional development markers; do not fail CI
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
