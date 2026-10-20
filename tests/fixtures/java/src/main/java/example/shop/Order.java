package example.shop;

import java.math.BigDecimal;

public record Order(int id, String status, BigDecimal total) {
}
