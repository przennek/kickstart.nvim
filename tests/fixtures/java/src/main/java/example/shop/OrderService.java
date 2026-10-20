package example.shop;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

public class OrderService {

    /** 5% off when at least 100 was spent in paid orders. */
    public BigDecimal loyaltyDiscount(List<Order> orders, BigDecimal newTotal) {
        BigDecimal spent = orders.stream()
                .filter(o -> o.status().equals("PAID"))
                .map(Order::total)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (spent.compareTo(new BigDecimal("100")) > 0) {
            return newTotal.multiply(new BigDecimal("0.05")).setScale(2, RoundingMode.HALF_UP);
        }
        return BigDecimal.ZERO;
    }
}
