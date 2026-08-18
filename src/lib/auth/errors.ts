export class AuthConfigurationError extends Error {
  constructor(message = "La autenticación todavía no está configurada en este entorno.") {
    super(message);
    this.name = "AuthConfigurationError";
  }
}
