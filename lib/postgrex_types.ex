Postgrex.Types.define(
  FinancialAdvisor.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
