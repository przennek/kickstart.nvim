package example.shop;

import java.math.BigDecimal;
import java.util.List;

public class App {
    public static void main(String[] args) {
        var orders = List.of(new Order(1, "PAID", new BigDecimal("150")));
        System.out.println("discount: " + new OrderService().loyaltyDiscount(orders, new BigDecimal("50")));
    }
}
