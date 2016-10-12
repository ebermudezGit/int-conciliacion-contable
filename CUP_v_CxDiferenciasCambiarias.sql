SET ANSI_NULLS, ANSI_WARNINGS ON;

GO 

-- =============================================
-- Created by:    Enrique Sierra Gtez
-- Creation Date: 2016-10-10
-- Last Modified: 2016-10-10 
--
-- Description: Desglosa las Diferencias Cambiarias 
--              de los Movimientos en Cxc y CxP.
-- 
 Example: SELECT * 
          FROM  CUP_v_CxDiferenciasCambiarias
          WHERE Modulo = 'CXP'
            AND ModuloID = 108870
--
--
-- =============================================


IF EXISTS(SELECT * FROM sysobjects WHERE name='CUP_v_CxDiferenciasCambiarias')
	DROP VIEW CUP_v_CxDiferenciasCambiarias
GO
CREATE VIEW CUP_v_CxDiferenciasCambiarias
AS

SELECT -- Cobros CXC
  c.Ejercicio,
  c.Periodo,
  Modulo = 'CXC',
  ModuloID = c.ID,
  Mov = c.Mov,
  MovId = c.MoviD,
  Fecha = c.FechaEmision,
  Documento = d.Aplica,
  DocumentoID = d.AplicaID,
  DocumentoTipo = dt.Clave,
  Moneda = c.ClienteMoneda,
  Importe = importe_aplica.Importe,
  TipoCambioReevaluado  = origen.TipoCambio,
  TipoCambioPago        = c.ClienteTipoCambio,
  ImporteMN_al_TC_Reevaluado = importes_calculo.ImporteMNTCOrigen,
  ImporteMN_al_TC_Pago = importes_calculo.ImporteMNTCAplica,
  Factor = dt.Factor,
  Diferencia_Cambiaria_MN = Round((  
                                    ISNULL(importes_calculo.ImporteMNTCAplica,0)
                                  - ISNULL(importes_calculo.ImporteMNTCOrigen,0)
                                  ) * dt.Factor,4,1)
FROM
  Cxc c 
JOIN Movtipo t ON t.Modulo = 'CXC'
              AND t.Mov = c.Mov 
JOIN cxcD d ON d.id = c.id
JOIN Movtipo dt ON dt.Modulo = 'CXC'
                AND dt.Mov = d.Aplica
JOIN cxc origen ON origen.Mov = d.Aplica
                AND origen.Movid = d.AplicaID
-- Importe Aplica 
CROSS APPLY( SELECT   
                FactorTC =   ROUND((c.TipoCambio / c.ClienteTipoCambio),4,1),
                Importe =  ROUND(d.Importe * (c.TipoCambio / c.ClienteTipoCambio),4,1)
            ) importe_aplica 
-- Ultima Rev
OUTER APPLY ( SELECT TOP 1  
                ur.ID ,
                TipoCambio = ur.ClienteTipoCambio
              FROM 
                  Cxc ur 
              JOIN CxcD urD ON  urD.Id = ur.ID
              JOIN Movtipo urt ON urt.Modulo = 'CXC'
                              AND urt.Mov =   ur.Mov
              WHERE
                urt.Clave = 'CXC.RE'
              AND ur.Estatus = 'CONCLUIDO'
              AND ur.FechaEmision < c.FechaRegistro 
              AND urD.Aplica = d.Aplica
              AND urD.AplicaID = d.AplicaID  
              ORDER BY 
                ur.ID DESC ) ultRev
-- Tipo de Cambio Historico
OUTER APPLY(
            SELECT 
              TipoCambio = ISNULL(ultRev.TipoCambio,origen.TipoCambio)
            ) historico
-- Importes MN para el calculo
CROSS APPLY( 
            SELECT
              ImporteMNTCOrigen =  ROUND(ISNULL(importe_aplica.Importe,0) *  origen.TipoCambio,4,1),
              ImporteMNTCAplica =  ROUND(ISNULL(importe_aplica.Importe,0) *  c.ClienteTipoCambio,4,1)
            ) importes_calculo

WHERE 
    c.Estatus = 'CONCLUIDO'
AND c.ClienteMoneda <> 'Pesos'
AND t.clave IN ('CXC.C','CXC.ANC')
AND ISNULL(d.Importe,0) <> 0
AND d.Aplica NOT IN ('Redondeo','Saldo a Favor')
AND dt.Clave <> 'CXC.NC'
UNION -- Aplicaciones CXC
SELECT
  c.Ejercicio,
  c.Periodo,
  Modulo = 'CXC',
  c.ID,
  Mov = c.Mov,
  MovId = c.MovID,
  Fecha = c.FechaEmision,
  Documento = c.MovAplica,
  DocumentoID = c.MovAplicaID,
  DocumentoTipo = mt.Clave,
  Moneda = c.Moneda,
  Importe = importe_aplica.Importe,
  TipoCambioReevaluado  = origen.TipoCambio,
  TipoCambioPago  = c.TipoCambio,
  ImporteMN_al_TC_Reevaluado = importes_calculo.ImporteMNTCOrigen,
  ImporteMN_al_TC_Pago = importes_calculo.ImporteMNTCAplica,
  Factor = mt.Factor,
  DiferenciaMN = Round((  
                          ISNULL(importes_calculo.ImporteMNTCAplica,0)
                        - ISNULL(importes_calculo.ImporteMNTCOrigen,0)
                        ) * mt.Factor,4,1)
FROM
  Cxc c 
JOIN Movtipo t ON t.Modulo = 'CXC'
              AND t.Mov = c.Mov 
JOIN cxc origen ON origen.Mov = c.MovAplica
                AND origen.Movid = c.MovAplicaID
JOIN Movtipo mt ON mt.Modulo = 'CXC'
                AND mt.Mov = c.MovAplica
-- Importe Aplica 
CROSS APPLY( SELECT   
                FactorTC =   1,
                Importe =  ROUND(ISNULL(c.Importe,0) 
                                + ISNULL(c.Impuestos,0) 
                                - ISNULL(c.Retencion,0),4,1)
            ) importe_aplica 
-- Ultima Rev
OUTER APPLY ( SELECT TOP 1  
                ur.ID ,
                TipoCambio = ur.ClienteTipoCambio
              FROM 
                  Cxc ur 
              JOIN CxcD urD ON  urD.Id = ur.ID
              JOIN Movtipo urt ON urt.Modulo = 'CXC'
                              AND urt.Mov =   ur.Mov
              WHERE
                urt.Clave = 'CXC.RE'
              AND ur.Estatus = 'CONCLUIDO'
              AND ur.FechaEmision < c.FechaRegistro 
              AND urD.Aplica = c.MovAplica
              AND urD.AplicaID = c.MovAplicaID
              ORDER BY 
                ur.ID DESC ) ultRev
-- Tipo de Cambio Historico
OUTER APPLY(
            SELECT 
              TipoCambio = ISNULL(ultRev.TipoCambio,origen.TipoCambio)
            ) historico
-- Importes MN para el calculo
CROSS APPLY( 
            SELECT
              ImporteMNTCHistorico  = ROUND(ISNULL(importe_aplica.Importe,0) *  historico.TipoCambio,4,1),
              ImporteMNTCOrigen =  ROUND(ISNULL(importe_aplica.Importe,0) *  origen.TipoCambio,4,1),
              ImporteMNTCAplica =  ROUND(ISNULL(importe_aplica.Importe,0) *  c.TipoCambio,4,1)
            ) importes_calculo
WHERE 
   c.Estatus = 'CONCLUIDO'
AND c.Moneda <> 'Pesos'
AND t.clave IN ('CXC.C','CXC.ANC')
AND ISNULL(c.Importe,0) <> 0
UNION -- Pagos Cxp
SELECT
  p.Ejercicio,
  p.Periodo,
  Modulo = 'CXP',
  ModuloID = p.ID,
  Mov = p.Mov,
  MovId = p.MovID,
  Fecha = p.FechaEmision,
  Documento = d.Aplica,
  DocumentoID = d.AplicaID,
  DocumentoTipo = dt.Clave,
  Moneda = p.ProveedorMoneda,
  Importe = importe_aplica.Importe,
  TipoCambioReevaluado  = historico.TipoCambio,
  TipoCambioPago  = p.ProveedorTipoCambio,
  ImporteMN_al_TC_Reevaluado = importes_calculo.ImporteMNTCOrigen,
  ImporteMN_al_TC_Pago = importes_calculo.ImporteMNTCAplica,
  Factor = -1,
  DiferenciaMN = ROUND((  
                          ISNULL(importes_calculo.ImporteMNTCAplica,0)
                        - ISNULL(importes_calculo.ImporteMNTCOrigen,0)
                       ) * -1,4,1)
FROM
  Cxp p 
JOIN Movtipo t ON t.Modulo = 'Cxp'
              AND t.Mov = p.Mov 
JOIN CxpD d ON d.id = p.id
JOIN Movtipo dt ON dt.Modulo = 'Cxp'
                AND dt.Mov = d.Aplica
JOIN Cxp origen ON origen.Mov = d.Aplica
            AND origen.Movid = d.AplicaID
-- Importe Aplica 
CROSS APPLY( SELECT   
                FactorTC =   ROUND((p.TipoCambio / p.ProveedorTipoCambio),4,1),
                Importe =  ROUND(d.Importe * (p.TipoCambio / p.ProveedorTipoCambio),4,1)
            ) importe_aplica 
-- Ultima Rev
OUTER APPLY ( SELECT TOP 1  
                ur.ID ,
                TipoCambio = ur.ProveedorTipoCambio
              FROM 
                  Cxp ur 
              JOIN CxpD urD ON  urD.Id = ur.ID
              JOIN Movtipo urt ON urt.Modulo = 'CXP'
                              AND urt.Mov =   ur.Mov
              WHERE
                urt.Clave = 'CXP.RE'
              AND ur.Estatus = 'CONCLUIDO'
              AND ur.FechaEmision < p.FechaRegistro 
              AND urD.Aplica = d.Aplica
              AND urD.AplicaID = d.AplicaID
              ORDER BY 
                ur.ID DESC ) ultRev
-- Tipo de Cambio Historico
OUTER APPLY(
            SELECT 
              TipoCambio = ISNULL(ultRev.TipoCambio,origen.TipoCambio)
            ) historico
-- Importes MN para el calculo
CROSS APPLY( 
            SELECT
              ImporteMNTCOrigen =  ROUND(ISNULL(importe_aplica.Importe,0) *  historico.TipoCambio,4,1),
              ImporteMNTCAplica =  ROUND(ISNULL(importe_aplica.Importe,0) *  p.ProveedorTipoCambio,4,1)
            ) importes_calculo
WHERE 
    p.Estatus = 'CONCLUIDO'
AND p.ProveedorMoneda <> 'Pesos'
AND t.clave IN ('CXP.P','CXP.ANC')
AND ISNULL(d.Importe,0) <> 0
AND d.Aplica NOT IN ('Redondeo','Saldo a Favor')
AND dt.Clave <> 'CXP.NC'
UNION -- Aplicaciones Pagos
SELECT
  p.Ejercicio,
  p.Periodo,
  Modulo = 'CXP',
  ModuloID = p.ID,
  Mov = p.Mov,
  MovID = p.MovID,
  Fecha = p.FechaEmision,
  Documento = p.MovAplica,
  DocumentoID = p.MovAplicaID,
  DocumentoTipo = mt.Clave,
  Moneda = p.Moneda,
  Importe         = importe_aplica.Importe,
  TipoCambioReevaluado  = historico.TipoCambio,
  TipoCambioPago  = p.TipoCambio,
  ImporteMN_al_TC_Reevaluado = importes_calculo.ImporteMNTCOrigen,
  ImporteMN_al_TC_Pago = importes_calculo.ImporteMNTCAplica,
  Factor = 1,
  DiferenciaMN = ROUND((  
                        ISNULL(importes_calculo.ImporteMNTCAplica,0)
                      - ISNULL(importes_calculo.ImporteMNTCOrigen,0)
                        ) * 1,4,1)
FROM
  CXP p
JOIN Movtipo t ON t.Modulo = 'CXP'
              AND t.Mov = p.Mov 
JOIN CXP origen ON origen.Mov = p.MovAplica
                AND origen.Movid = p.MovAplicaID
JOIN Movtipo mt ON mt.Modulo = 'CXP'
                AND mt.Mov = p.MovAplica
-- Importe Aplica 
CROSS APPLY( SELECT   
                FactorTC =   1,
                Importe =  ROUND(ISNULL(p.Importe,0) 
                                + ISNULL(p.Impuestos,0) 
                                - ISNULL(p.Retencion,0),4,1)
            ) importe_aplica 
-- Ultima Rev
OUTER APPLY ( SELECT TOP 1  
                ur.ID ,
                TipoCambio = ur.ProveedorTipoCambio
              FROM 
                  Cxp ur 
              JOIN CxpD urD ON  urD.Id = ur.ID
              JOIN Movtipo urt ON urt.Modulo = 'CXP'
                              AND urt.Mov =   ur.Mov
              WHERE
                urt.Clave = 'CXP.RE'
              AND ur.Estatus = 'CONCLUIDO'
              AND ur.FechaEmision < p.FechaRegistro 
              AND urD.Aplica = p.MovAplica
              AND urD.AplicaID = p.MovAplicaID
              ORDER BY 
                ur.ID DESC ) ultRev
-- Tipo de Cambio Historico
OUTER APPLY(
            SELECT 
              TipoCambio = ISNULL(ultRev.TipoCambio,origen.TipoCambio)
            ) historico
-- Importes MN para el calculo
CROSS APPLY( 
            SELECT
              ImporteMNTCOrigen =  ROUND(ISNULL(importe_aplica.Importe,0) *  historico.TipoCambio,4,1),
              ImporteMNTCAplica =  ROUND(ISNULL(importe_aplica.Importe,0) *  p.ProveedorTipoCambio,4,1)
            ) importes_calculo
WHERE 
   p.Estatus = 'CONCLUIDO'
AND p.Moneda <> 'Pesos'
AND t.clave IN ('CXP.P','CXP.ANC')
AND ISNULL(p.Importe,0) <> 0
 