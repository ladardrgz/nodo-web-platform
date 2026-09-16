# Agregar un caso de uso

1. Definí la regla o el dato de entrada en `domain` o `application/dto`.
2. Agregá el método mínimo al contrato de repositorio.
3. Creá `application/use-cases/<Nombre>UseCase.ts` que dependa del contrato.
4. Implementalo en Infrastructure con una query o RPC transaccional.
5. Exponelo por una Server Action delgada en Presentation.
6. Agregá pruebas de dominio y, si modifica datos, una validación de PostgreSQL/RPC.

No uses un `utils.ts` genérico ni pases `organizationId` desde React. Si el caso modifica varios registros, preferí una RPC transaccional con constraints verificables.
