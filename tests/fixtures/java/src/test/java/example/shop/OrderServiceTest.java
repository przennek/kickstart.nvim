package example.shop;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class OrderServiceTest {
    private final OrderService service = new OrderService();

    @Test
    void noDiscountForNewCustomer() {
        assertEquals(BigDecimal.ZERO, service.loyaltyDiscount(List.of(), new BigDecimal("50")));
    }

    @Test
    void discountFromExactly100Paid() {
        var orders = List.of(new Order(1, "PAID", new BigDecimal("100")));
        assertEquals(new BigDecimal("2.50"), service.loyaltyDiscount(orders, new BigDecimal("50")));
    }
}
