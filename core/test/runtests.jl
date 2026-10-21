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
