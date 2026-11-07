import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

// The three strips contain only the public Uzbek role labels from the reviewed
// iPhone 16 Pro QA screenshot. System UI, time and account data are excluded.
class RoleScreen {
    static boolean dark(BufferedImage image, int x, int y) {
        int color = image.getRGB(x, y);
        int red = (color >> 16) & 255;
        int green = (color >> 8) & 255;
        int blue = color & 255;
        return red * 299 + green * 587 + blue * 114 < 100000;
    }

    static boolean matches(BufferedImage screen, BufferedImage reference, int row, int left, int top) {
        int sharedInk = 0;
        int allInk = 0;
        for (int y = 0; y < 80; y++) {
            for (int x = 0; x < 500; x++) {
                boolean actual = dark(screen, left + x, top + y);
                boolean expected = dark(reference, x, row * 80 + y);
                if (actual && expected) sharedInk++;
                if (actual || expected) allInk++;
            }
        }
        return sharedInk > 0 && sharedInk >= 0.9 * allInk;
    }

    public static void main(String[] args) throws Exception {
        BufferedImage screen = ImageIO.read(new File(args[0]));
        BufferedImage reference = ImageIO.read(new File("tool/fixtures/iphone16pro-uz-role-labels.png"));
        if (screen == null || screen.getWidth() != 1206 || screen.getHeight() != 2622) {
            System.exit(1);
        }
        boolean customer = matches(screen, reference, 0, 70, 1794);
        boolean sitter = matches(screen, reference, 1, 650, 1794);
        boolean proceed = matches(screen, reference, 2, 350, 2310);
        System.out.printf("Role screen labels: Mijozman=%b Enagaman=%b Davom etish=%b%n",
                          customer, sitter, proceed);
        System.exit(customer && sitter && proceed ? 0 : 1);
    }
}
