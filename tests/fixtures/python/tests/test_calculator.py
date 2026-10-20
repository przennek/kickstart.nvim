from shop.calculator import Line, PriceCalculator


def test_no_discount():
    assert PriceCalculator(10).final_price([Line("Book", 100, 1)]) == 100


def test_bulk_discount():
    assert PriceCalculator(10).final_price([Line("Apple", 2.5, 12)]) == 27
