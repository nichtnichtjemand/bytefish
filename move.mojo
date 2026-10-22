from std.collections import Optional


struct Move(Copyable, ImplicitlyCopyable, Movable):
    var from_field: String
    var to_field: String
    var promotion: Optional[String]

    var from_column: Int
    var from_row: Int
    var to_column: Int
    var to_row: Int

    def __init__(
        out self,
        from_field: String,
        to_field: String,
        promotion: Optional[String] = None,
    ) raises:
        self.from_field = from_field
        self.to_field = to_field
        self.promotion = promotion

        self.from_column = -1
        self.from_row = -1
        self.to_column = -1
        self.to_row = -1

        if from_field.byte_length() >= 2 and to_field.byte_length() >= 2:
            var from_bytes = from_field.lower().as_bytes()
            var to_bytes = to_field.lower().as_bytes()

            self.from_column = Int(from_bytes[0]) - 97
            self.from_row = 8 - (Int(from_bytes[1]) - 48)

            self.to_column = Int(to_bytes[0]) - 97
            self.to_row = 8 - (Int(to_bytes[1]) - 48)

    def __init__(
        out self,
        from_row: Int,
        from_column: Int,
        to_row: Int,
        to_column: Int,
        promotion: Optional[String] = None,
    ):
        self.from_row = from_row
        self.from_column = from_column
        self.to_row = to_row
        self.to_column = to_column
        self.from_field = (
            String(chr(97 + from_column)) + String(chr(56 - from_row))
        )
        self.to_field = String(chr(97 + to_column)) + String(chr(56 - to_row))
        self.promotion = promotion

    def __str__(self) -> String:
        var promo_str = String("")

        if self.promotion:
            promo_str = " Promotion: " + self.promotion.value()

        return "From: " + self.from_field + " To: " + self.to_field + promo_str

    def __repr__(self) -> String:
        return self.__str__()
