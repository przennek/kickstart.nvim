# Plays an LLM agent editing the Java fixture behind the editor's back
import pathlib, sys
root = pathlib.Path(sys.argv[1])
svc = root / 'src/main/java/example/shop/OrderService.java'
s = svc.read_text().replace('compareTo(new BigDecimal("100")) > 0', 'compareTo(new BigDecimal("100")) >= 0')
s = s.replace('    }\n}\n', '    }\n\n    public long unpaid(List<Order> orders) {\n        return orders.stream().filter(o -> o.status().equals("NEW")).count();\n    }\n}\n')
svc.write_text(s)
(root / 'src/main/java/example/shop/Customer.java').write_text('package example.shop;\n\npublic record Customer(int id, String name) {\n}\n')
t = root / 'src/test/java/example/shop/OrderServiceTest.java'
t.write_text(t.read_text().replace('    }\n}\n', '    }\n\n    @Test\n    void countsUnpaid() {\n        assertEquals(1, service.unpaid(List.of(new Order(1, "NEW", BigDecimal.ONE))));\n    }\n}\n'))
