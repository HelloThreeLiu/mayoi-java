package demo;

public class App {
    public static void main(String[] args) {
        String message = greet("Mayoi");
        System.out.println(message);
    }

    static String greet(String name) {
        return "Hello, " + name + "!";
    }
}
