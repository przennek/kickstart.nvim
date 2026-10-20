from dataclasses import dataclass


@dataclass
class Line:
    product: str
    price: float
    quantity: int

    def total(self) -> float:
        return self.price * self.quantity


class PriceCalculator:
    def __init__(self, min_items: int):
        self.min_items = min_items

    def final_price(self, lines: list[Line]) -> float:
        total = sum(line.total() for line in lines)
        items = sum(line.quantity for line in lines)
        if items >= self.min_items:
            return round(total * 0.9, 2)
        return total


if __name__ == "__main__":
    print("Final price:", PriceCalculator(10).final_price([Line("Apple", 2.5, 12)]))
