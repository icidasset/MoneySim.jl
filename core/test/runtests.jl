using Test
using MoneySimCore
using EconoSimCore

@testset "MoneySimCore" begin
    @testset "validation" begin
        @test validate_config(SimConfig()) == CONFIG_OK

        bad = SimConfig(periods = 0)
        @test validate_config(bad) == CONFIG_BAD_PERIODS

        bad = SimConfig(periods = 10, record_interval = 3)
        @test validate_config(bad) == CONFIG_BAD_RECORD_INTERVAL

        bad = SimConfig(population = PopulationConfig(count = 0))
        @test validate_config(bad) == CONFIG_BAD_POPULATION

        bad = SimConfig(wealth = WealthConfig(
            distribution = WealthDistribution.CUSTOM,
            custom = [money(1)]), population = PopulationConfig(count = 2))
        @test validate_config(bad) == CONFIG_BAD_WEALTH

        @test_throws ConfigError run_simulation(bad)
    end

    @testset "equal wealth, no dynamics" begin
        cfg = SimConfig(
            periods = 10,
            record_interval = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 10,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 10
        @test result.mean[end] == 100.0
        @test result.total[end] == 1_000.0
        @test result.min[end] == 100.0
        @test result.max[end] == 100.0
        @test result.gini[end] == 0.0
        @test result.income_gini[end] == -1.0
        @test result.tax_collected[end] == 0.0

        base = (10 - 1) * 6
        @test result.shares[base + 3] == 0.5  # bottom 50%
        @test result.shares[base + 4] == 0.9  # bottom 90%
        @test result.shares[base + 6] == 1.0  # bottom 99.9%
    end

    @testset "SUMSY convergence" begin
        cfg = SimConfig(
            periods = 30_000,
            record_interval = 30,
            population = PopulationConfig(count = 100),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(0)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 30,
                                guaranteed_income = money(2_000),
                                demurrage = make_tiers(0.01)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 1_000
        @test isapprox(result.mean[end], 200_000.0; rtol = 1e-4)
        @test isapprox(result.total[end], 20_000_000.0; rtol = 1e-4)
        @test result.gini[end] == 0.0
    end

    @testset "income tax" begin
        state = SimState(3)
        state.wealth[1] = money(1_000)
        state.wealth[2] = money(1_000)
        state.wealth[3] = money(1_000)
        state.income[1] = money(1_000)
        state.income[2] = money(2_000)
        state.income[3] = money(5_000)

        brackets = [money(1_000), money(5_000), typemax(Money)]
        cfg = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = brackets,
                        bracket_rates = Int64[1_000, 2_000, 3_000])

        collected = tax_step_income!(state, cfg, 1)
        @test collected == money(1_300)
        @test state.income == fill(zero(Money), 3)
        @test state.wealth[1] == money(900)
        @test state.wealth[2] == money(700)
        @test state.wealth[3] == money(100)
        @test state.tax_scale == 1.0

        state = SimState(3)
        state.wealth .= money(1_000)
        state.income[1] = money(1_000)
        state.income[2] = money(2_000)
        state.income[3] = money(5_000)
        cfg = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = brackets,
                        bracket_rates = Int64[1_000, 2_000, 3_000],
                        target_revenue = money(650),
                        scale_to_target = true)
        collected = tax_step_income!(state, cfg, 1)
        @test collected == money(650)
        @test isapprox(state.tax_scale, 0.5; atol = 1e-9)
    end

    @testset "government deficit" begin
        state = SimState(10)
        state.wealth .= money(1_000)
        tax = TaxConfig(kind = TaxKind.NONE)

        government = GovernmentConfig(enabled = true,
                                      expenses = money(1_500),
                                      deficit_spending = true)
        government_step!(state, government, tax, MONEY_ZERO)
        @test state.government_debt == money(1_500)
        @test total_wealth(state) == money(11_500)

        state = SimState(10)
        state.wealth .= money(1_000)
        government = GovernmentConfig(enabled = true,
                                      expenses = money(1_500),
                                      deficit_spending = false)
        government_step!(state, government, tax, money(1_000))
        @test state.government_debt == MONEY_ZERO
        @test total_wealth(state) == money(10_000)
    end

    @testset "yard sale conserves money" begin
        cfg = SimConfig(
            periods = 100,
            record_interval = 10,
            population = PopulationConfig(count = 50),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = true,
                                             transactions_per_step = 200,
                                             transfer_rate = 0.2,
                                             wealth_advantage = 0.2),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 10
        @test isapprox(result.total[end], 50_000.0; rtol = 1e-9)
        @test result.gini[end] > 0.0
        @test result.income_gini[end] >= 0.0
    end

    @testset "demographics" begin
        function run_state(population; periods = 1)
            cfg = SimConfig(
                periods = periods,
                population = population,
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(100)),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = false))
            state = SimState(population.count)
            results = ResultBuffers(periods)
            run_simulation!(cfg, state, results)
            return state, results
        end

        births, birth_results = run_state(PopulationConfig(
            count = 10, birth_rate = 0.1, birth_wealth = money(50), typed_gi = true))
        @test births.n == 11
        @test alive_count(births) == 11
        @test births.wealth[11] == money(50)
        @test birth_results.total[end] == 1_050.0

        deaths, death_results = run_state(PopulationConfig(count = 10, death_rate = 0.1))
        @test alive_count(deaths) == 9
        @test death_results.total[end] == 900.0

        aged, _ = run_state(PopulationConfig(
            count = 10, aging_interval = 1, aging_rate = 1.0,
            typed_gi = true, gi_child = false, gi_adult = true, gi_elder = true))
        @test all(==(UInt8(1)), aged.age_type)
        @test all(==(UInt8(1)), aged.gi_eligible)
    end

    @testset "adaptations" begin
        injected = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            adaptations = AdaptationConfig(inject_enabled = true,
                                           inject_amount = money(1_000),
                                           inject_interval = 1)))
        @test injected.total[end] == 2_000.0

        destroyed = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            adaptations = AdaptationConfig(destroy_enabled = true,
                                           destroy_amount = money(1_000),
                                           destroy_interval = 1)))
        @test destroyed.total[end] == 9_000.0
    end

    @testset "GDP volume target" begin
        cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false,
                                             transfer_rate = 0.2),
            gdp = GdpConfig(enabled = true, per_capita = money(50)))

        state = SimState(cfg.population.count)
        results = ResultBuffers(1)
        run_simulation!(cfg, state, results)
        @test sum(state.income) >= money(500)
        @test total_wealth(state) == money(10_000)
    end

    @testset "wealth tax" begin
        function tax_result(kind; actor = 0)
            cfg = SimConfig(
                periods = 1,
                record_interval = 1,
                population = PopulationConfig(count = 10),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(1_000)),
                money = MoneyConfig(model = MoneyModel.SUMSY,
                                    interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = false),
                tax = TaxConfig(kind = TaxKind.WEALTH, rate = 0.10, interval = 1,
                                recipient = kind, recipient_actor = actor))
            return run_simulation(cfg)
        end

        everyone = tax_result(TaxRecipient.EVERYONE)
        @test everyone.tax_collected[end] == 1_000.0
        @test isapprox(everyone.total[end], 10_000.0; rtol = 1e-9)
        @test everyone.gini[end] == 0.0

        destroy = tax_result(TaxRecipient.DESTROY)
        @test destroy.tax_collected[end] == 1_000.0
        @test isapprox(destroy.total[end], 9_000.0; rtol = 1e-9)

        one = tax_result(TaxRecipient.ONE_ACTOR; actor = 1)
        @test isapprox(one.total[end], 10_000.0; rtol = 1e-9)
        @test one.gini[end] > 0.0

        first_n = tax_result(TaxRecipient.FIRST_N; actor = 2)
        @test isapprox(first_n.total[end], 10_000.0; rtol = 1e-9)
        @test first_n.gini[end] > 0.0
    end

    @testset "custom and concentrated wealth" begin
        custom = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 3),
            wealth = WealthConfig(distribution = WealthDistribution.CUSTOM,
                                  custom = [money(100), money(200), money(300)]),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE)))
        @test custom.total[end] == 600.0
        @test custom.min[end] == 100.0
        @test custom.max[end] == 300.0

        concentrated = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.CONCENTRATED,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE)))
        @test concentrated.total[end] == 1_000.0
        @test isapprox(concentrated.gini[end], 0.9; atol = 1e-9)
    end

    @testset "bank" begin
        cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0), interest_rate = 0),
            transactions = TransactionConfig(enabled = false),
            bank = BankConfig(enabled = true, actor_index = 1,
                              lending_amount = money(1_000),
                              lending_targets = 2))
        state = SimState(10)
        results = ResultBuffers(1)
        run_simulation!(cfg, state, results)
        @test state.wealth[2] == money(1_500)
        @test state.wealth[3] == money(1_500)
        @test state.debt[2] == money(500)
        @test state.debt[3] == money(500)
        @test total_wealth(state) == money(11_000)

        state = SimState(2)
        state.wealth .= money(1_000)
        state.debt[2] = money(1_000)
        money_cfg = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                interest_rate = permyriad(0.01))
        bank = BankConfig(enabled = true, actor_index = 1)
        bank_step!(state, money_cfg, bank)
        @test state.wealth[1] == money(1_010)
        @test state.wealth[2] == money(990)

        state = SimState(2)
        state.wealth .= money(1_000)
        state.debt[2] = money(1_000)
        bank = BankConfig(enabled = true, actor_index = 1,
                          repayment_rate = 0.1)
        repay_cfg = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                interest_rate = 0)
        bank_step!(state, repay_cfg, bank)
        @test state.wealth[2] == money(900)
        @test state.debt[2] == money(900)
    end

    @testset "loan circuit" begin
        # Growth mode: each balance accrues g; p is converted to bank reserves.
        growth_cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 2),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                interest_rate = permyriad(0.10)),
            transactions = TransactionConfig(enabled = false),
            loan_circuit = LoanCircuitConfig(enabled = true,
                                             profit_rate = 0.05,
                                             maturity = 1, mode = 0))
        state = SimState(2)
        results = ResultBuffers(1)
        run_simulation!(growth_cfg, state, results)
        @test state.wealth[1] == money(1_100)
        @test state.wealth[2] == money(1_100)
        @test state.debt[1] == money(1_150)
        @test state.bank_reserve == money(100)
        @test total_wealth(state) == money(2_200)

        # Loan-rate mode: one cycle should grow the pool by the paper's formula.
        function loan_cfg(periods, profit; seed = 42)
            SimConfig(
                periods = periods,
                seed = seed,
                population = PopulationConfig(count = 100),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(100)),
                money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                    interest_rate = permyriad(0.15)),
                transactions = TransactionConfig(enabled = true,
                                                 transactions_per_step = 2_000,
                                                 transfer_rate = 0.2,
                                                 wealth_advantage = 0.0),
                loan_circuit = LoanCircuitConfig(enabled = true,
                                                 profit_rate = profit,
                                                 maturity = 20, mode = 1))
        end

        one = run_simulation(loan_cfg(1, 0.008))
        @test isapprox(one.total[1], 11_082.35; atol = 0.01)

        stable = run_simulation(loan_cfg(500, 0.008))
        @test stable.periods == 500
        @test isapprox(stable.total[end], 720_271_164_192_546.0; rtol = 1e-9)

        collapsed = run_simulation(loan_cfg(500, 0.009))
        @test collapsed.periods == 193
        @test isapprox(collapsed.total[end], 842_970.5606; rtol = 1e-9)
    end

    @testset "countries" begin
        be = belgium()
        @test population_total(be) == 11_697_556
        @test money_per_capita(be) == div(be.money_stock, 11_697_556)
        @test gdp_per_capita(be) == div(be.government.gdp, 11_697_556)

        values = unequal_wealth(be, 1_000)
        @test length(values) == 1_000
        @test maximum(values) > minimum(values)
        @test isapprox(currency(sum(values)),
                       currency(money_per_capita(be)) * 1_000; rtol = 1e-6)

        cfg = country_config(be; actors = 200, periods = 12,
                             wealth_distribution = WealthDistribution.CUSTOM,
                             tax_kind = TaxKind.NONE,
                             government_enabled = false,
                             record_interval = 12)
        result = run_simulation(cfg)
        @test result.periods == 1
        @test isfinite(result.gini[1])
        @test result.total[1] > 0

        # Paper-3 direction checks at a 1,000-actor sample.
        a1 = country_config(be; actors = 1_000, periods = 120,
                            wealth_distribution = WealthDistribution.CUSTOM,
                            tax_kind = TaxKind.NONE,
                            government_enabled = false,
                            record_interval = 12)
        r1 = run_simulation(a1)
        @test 0.40 < r1.gini[end] < 0.50
        @test isapprox(r1.mean[end], currency(money_per_capita(be)); rtol = 0.01)

        target = div((be.government.expenses - be.government.interest_cost) * 1_000,
                     population_total(be))
        a3 = country_config(be; actors = 1_000, periods = 120,
                            wealth_distribution = WealthDistribution.CUSTOM,
                            tax_kind = TaxKind.INCOME, tax_interval = 12,
                            target_revenue = target,
                            government_enabled = false,
                            record_interval = 12)
        r3 = run_simulation(a3)
        @test r3.tax_collected[end] > 0
        @test r3.gini[end] < r1.gini[end]
    end

    @testset "determinism" begin
        function noisy(seed)
            cfg = SimConfig(
                periods = 50,
                record_interval = 5,
                seed = seed,
                population = PopulationConfig(count = 30),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(1_000)),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = true,
                                                 transactions_per_step = 50,
                                                 transfer_rate = 0.2),
                tax = TaxConfig(kind = TaxKind.NONE))
            return run_simulation(cfg).gini
        end

        @test noisy(7) == noisy(7)
        @test noisy(7) != noisy(8)
    end
end
