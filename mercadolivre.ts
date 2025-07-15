import { SecretsManagerClient, GetSecretValueCommand, PutSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from "axios";

// Interfaces
interface MLCredentials {
  client_id: string;
  client_secret: string;
  refresh_token: string;
  access_token?: string;
  expires_at?: number; // timestamp
}

interface MLTokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  scope: string;
  user_id: number;
  refresh_token: string;
}

interface MLApiResponse<T = any> {
  data: T;
  status: number;
  headers: any;
}

export class MercadoLivre {
  private secretsClient: SecretsManagerClient;
  private httpClient: AxiosInstance;
  private credentials: MLCredentials | null = null;
  private readonly secretName: string;
  private readonly baseURL: string;

  constructor(secretName: string, region: string = "us-east-1") {
    this.secretName = secretName;
    this.secretsClient = new SecretsManagerClient({ region });
    this.baseURL = "https://api.mercadolibre.com";
    
    this.httpClient = axios.create({
      baseURL: this.baseURL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });

    // Interceptor para adicionar token nas requisições
    this.httpClient.interceptors.request.use(async (config) => {
      await this.ensureValidToken();
      if (this.credentials?.access_token) {
        config.headers.Authorization = `Bearer ${this.credentials.access_token}`;
      }
      return config;
    });

    // Interceptor para tratar respostas de erro
    this.httpClient.interceptors.response.use(
      (response) => response,
      async (error) => {
        if (error.response?.status === 401) {
          // Token inválido, força refresh
          await this.refreshAccessToken();
          // Retry da requisição original
          return this.httpClient.request(error.config);
        }
        return Promise.reject(error);
      }
    );
  }

  /**
   * Carrega as credenciais do AWS Secrets Manager
   */
  private async loadCredentials(): Promise<MLCredentials> {
    try {
      const command = new GetSecretValueCommand({
        SecretId: this.secretName,
      });

      const response = await this.secretsClient.send(command);
      
      if (!response.SecretString) {
        throw new Error("Secret não encontrado ou vazio");
      }

      const credentials = JSON.parse(response.SecretString) as MLCredentials;
      
      // Valida se as credenciais obrigatórias existem
      if (!credentials.client_id || !credentials.client_secret || !credentials.refresh_token) {
        throw new Error("Credenciais incompletas no Secrets Manager");
      }

      return credentials;
    } catch (error) {
      let message = 'Erro ao carregar credenciais';
      if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Salva as credenciais no AWS Secrets Manager
   */
  private async saveCredentials(credentials: MLCredentials): Promise<void> {
    try {
      const command = new PutSecretValueCommand({
        SecretId: this.secretName,
        SecretString: JSON.stringify(credentials),
      });

      await this.secretsClient.send(command);
    } catch (error) {
      let message = 'Erro ao salvar credenciais';
      if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Verifica se o token precisa ser renovado (menos de 1 hora para expirar)
   */
  private needsRefresh(): boolean {
    if (!this.credentials?.access_token || !this.credentials?.expires_at) {
      return true;
    }

    const now = Date.now();
    const oneHourInMs = 60 * 60 * 1000;
    const expiresAt = this.credentials.expires_at;

    return (expiresAt - now) < oneHourInMs;
  }

  /**
   * Executa o refresh do access token
   */
  private async refreshAccessToken(): Promise<void> {
    if (!this.credentials) {
      this.credentials = await this.loadCredentials();
    }

    try {
      const response = await axios.post<MLTokenResponse>(
        `${this.baseURL}/oauth/token`,
        {
          grant_type: 'refresh_token',
          client_id: this.credentials.client_id,
          client_secret: this.credentials.client_secret,
          refresh_token: this.credentials.refresh_token,
        },
        {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        }
      );

      const tokenData = response.data;
      
      // Atualiza as credenciais
      this.credentials = {
        ...this.credentials,
        access_token: tokenData.access_token,
        refresh_token: tokenData.refresh_token,
        expires_at: Date.now() + (tokenData.expires_in * 1000),
      };

      // Salva as credenciais atualizadas
      await this.saveCredentials(this.credentials);
      
      console.log('Token renovado com sucesso');
    } catch (error) {
      let message = 'Erro ao renovar token';
      if (typeof error === 'object' && error !== null && 'response' in error && typeof (error as any).response?.data?.message === 'string') {
        message += `: ${(error as any).response.data.message}`;
      } else if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Garante que temos um token válido
   */
  private async ensureValidToken(): Promise<void> {
    if (!this.credentials) {
      this.credentials = await this.loadCredentials();
    }

    if (this.needsRefresh()) {
      await this.refreshAccessToken();
    }
  }

  /**
   * Método genérico para fazer requisições GET
   */
  public async get<T = any>(endpoint: string, config?: AxiosRequestConfig): Promise<MLApiResponse<T>> {
    try {
      const response = await this.httpClient.get<T>(endpoint, config);
      return {
        data: response.data,
        status: response.status,
        headers: response.headers,
      };
    } catch (error) {
      let message = `Erro na requisição GET ${endpoint}`;
      if (typeof error === 'object' && error !== null && 'response' in error && typeof (error as any).response?.data?.message === 'string') {
        message += `: ${(error as any).response.data.message}`;
      } else if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Método genérico para fazer requisições POST
   */
  public async post<T = any>(endpoint: string, data?: any, config?: AxiosRequestConfig): Promise<MLApiResponse<T>> {
    try {
      const response = await this.httpClient.post<T>(endpoint, data, config);
      return {
        data: response.data,
        status: response.status,
        headers: response.headers,
      };
    } catch (error) {
      let message = `Erro na requisição POST ${endpoint}`;
      if (typeof error === 'object' && error !== null && 'response' in error && typeof (error as any).response?.data?.message === 'string') {
        message += `: ${(error as any).response.data.message}`;
      } else if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Método genérico para fazer requisições PUT
   */
  public async put<T = any>(endpoint: string, data?: any, config?: AxiosRequestConfig): Promise<MLApiResponse<T>> {
    try {
      const response = await this.httpClient.put<T>(endpoint, data, config);
      return {
        data: response.data,
        status: response.status,
        headers: response.headers,
      };
    } catch (error) {
      let message = `Erro na requisição PUT ${endpoint}`;
      if (typeof error === 'object' && error !== null && 'response' in error && typeof (error as any).response?.data?.message === 'string') {
        message += `: ${(error as any).response.data.message}`;
      } else if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  /**
   * Método genérico para fazer requisições DELETE
   */
  public async delete<T = any>(endpoint: string, config?: AxiosRequestConfig): Promise<MLApiResponse<T>> {
    try {
      const response = await this.httpClient.delete<T>(endpoint, config);
      return {
        data: response.data,
        status: response.status,
        headers: response.headers,
      };
    } catch (error) {
      let message = `Erro na requisição DELETE ${endpoint}`;
      if (typeof error === 'object' && error !== null && 'response' in error && typeof (error as any).response?.data?.message === 'string') {
        message += `: ${(error as any).response.data.message}`;
      } else if (error instanceof Error) {
        message += `: ${error.message}`;
      }
      throw new Error(message);
    }
  }

  // Métodos específicos para operações comuns do Mercado Livre

  /**
   * Obtém informações do usuário atual
   */
  public async getUser(): Promise<MLApiResponse> {
    return this.get('/users/me');
  }

  /**
   * Obtém anúncios do usuário
   */
  public async getItems(sellerId: string, status?: string): Promise<MLApiResponse> {
    const params = new URLSearchParams();
    if (status) params.append('status', status);
    
    const queryString = params.toString();
    const endpoint = `/users/${sellerId}/items/search${queryString ? `?${queryString}` : ''}`;
    
    return this.get(endpoint);
  }

  /**
   * Obtém detalhes de um item específico
   */
  public async getItem(itemId: string): Promise<MLApiResponse> {
    return this.get(`/items/${itemId}`);
  }

  /**
   * Cria um novo anúncio
   */
  public async createItem(itemData: any): Promise<MLApiResponse> {
    return this.post('/items', itemData);
  }

  /**
   * Atualiza um anúncio existente
   */
  public async updateItem(itemId: string, itemData: any): Promise<MLApiResponse> {
    return this.put(`/items/${itemId}`, itemData);
  }

  /**
   * Obtém pedidos do usuário
   */
  public async getOrders(sellerId: string, status?: string): Promise<MLApiResponse> {
    const params = new URLSearchParams();
    if (status) params.append('order.status', status);
    
    const queryString = params.toString();
    const endpoint = `/orders/search/recent${queryString ? `?${queryString}` : ''}`;
    
    return this.get(endpoint);
  }

  /**
   * Obtém detalhes de um pedido específico
   */
  public async getOrder(orderId: string): Promise<MLApiResponse> {
    return this.get(`/orders/${orderId}`);
  }

  /**
   * Obtém mensagens de um pedido
   */
  public async getOrderMessages(orderId: string): Promise<MLApiResponse> {
    return this.get(`/messages/orders/${orderId}`);
  }

  /**
   * Força a renovação do token (útil para testes)
   */
  public async forceTokenRefresh(): Promise<void> {
    await this.refreshAccessToken();
  }
}