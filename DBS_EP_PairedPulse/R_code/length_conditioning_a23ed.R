setwd('C:/Users/david/SharedCode/DBSanalysisCode')

library('plyr')
library('here')
library('nlme')
library('ggplot2')
library('drc')
library('minpack.lm')
library('lmtest')
library('glmm')
library("lme4")
library('multcomp')
library('lmerTest')
library('sjPlot')
library('emmeans')
library("dplyr")

rootDir = here()
dataDir = here("DBS_EP_PairedPulse","R_data")
codeDir = here("DBS_EP_PairedPulse","R_code")

sidVec = c("a23ed")


repeatedMeasures = FALSE # if true, does repeated measures analysis, if false, does more of ANCOVA style analysis
min_stim_level = 2
log_data = TRUE
box_data = FALSE
trim_data = TRUE
savePlot = 0
avgMeasVec = c(0)
figWidth = 8 
figHeight = 4

dataList = list()
blockList = list()
conditionList = list()
index = 1

# hardcode subject #
subjectNum = 11

for (avgMeas in avgMeasVec) {
  for (sid in sidVec){
    source(here("DBS_EP_PairedPulse","R_config_files",paste0("subj_",sid,".R")))
    
    # just modifiy a23ed
    whichCompareVec = list(c(2,3),c(5,6))
    blockType = c('baseline','baseline','A/B 200 ms 5 minutes','baseline','baseline',
                  'A/B 200 ms 15 minutes','baseline','A/A 200','baseline')
    
    if (avgMeas) {
      dataPP <- read.table(here("DBS_EP_PairedPulse","R_data",paste0(sid,'_PairedPulseData_avg.csv')),header=TRUE,sep = ",",stringsAsFactors=F, colClasses=c("stimLevelVec"="numeric","sidVec"="character"))
    } else{
      dataPP <- read.table(here("DBS_EP_PairedPulse","R_data",paste0(sid,'_PairedPulseData_new.csv')),header=TRUE,sep = ",",stringsAsFactors=F, colClasses=c("stimLevelVec"="numeric","sidVec"="character"))
    }
    
    # multiply by 1e6
    dataPP$PPvec = dataPP$PPvec*1e6
    dataPP$stimLevelVec = dataPP$stimLevelVec/1e3
    dataPP <- subset(dataPP, PPvec<1000)
    dataPP <- subset(dataPP, PPvec>30)
    
    # denote which channel was in the conditioning pair 
    
    dataPP <- subset(dataPP,(chanVec %in% chanIntVec))
    
    dataPP$chanInCond <- mapvalues(dataPP$chanVec,
                                   from=chanIntVec,
                                   to=chanIntConditioningPairVec)
    # change to factor 
    dataPP$blockVec = as.factor(dataPP$blockVec)
    print(sid)
    
    for (chanInt in chanIntVec){
      
      # select data of interest 
      dataInt <- na.exclude(subset(dataPP,(chanVec == chanInt) & (blockVec %in% blockIntPlot)))
      
      # map stimulation levels to consistent ordering for between subject comparison
      uniqueStimLevel = as.double(unique(dataInt$stimLevelVec))
      
      if (sid == "2e114"){
        mappingStimLevel =c(1,3,4)
        
      } else {
        mappingStimLevel =c(1:length(uniqueStimLevel))
      }
      dataInt$mapStimLevel<- mapvalues(dataInt$stimLevelVec,
                                       from=sort(uniqueStimLevel),
                                       to=mappingStimLevel)
      
      #uniqueBlockLevel = unique(dataInt$blockVec)
      #blockTypeTrim = blockType[uniqueBlockLevel]
      
      #dataInt$blockType <- mapvalues(dataInt$blockVec,
      #                               from=uniqueBlockLevel,
      #                               to=blockTypeTrim)
      
      
      dataInt$blockType <- mapvalues(dataInt$blockVec,
                                     from=blockIntPlot,
                                     to=blockType)
      
      dataInt$mapStimLevel = as.ordered(dataInt$mapStimLevel)
      dataInt$blockType = as.factor(dataInt$blockType)
      
      if (trim_data){
        dataInt <- dataInt %>% group_by(blockVec,blockType,mapStimLevel) %>% mutate(PPvecLabel = !is.element(seq_len(length(PPvec)),attr(Trim(PPvec,0.025,na.rm=FALSE),'trim')))
        dataInt <- subset(dataInt,PPvecLabel==TRUE)
        
      }
      
      dataInt <- subset(dataInt,mapStimLevel>=min_stim_level)
      
      if (log_data){
        dataInt$PPvec <- log(dataInt$PPvec)
      }
      
      if (box_data){
        box_trans <- caret::BoxCoxTrans(dataInt$PPvec)
        dataInt$PPvec <- predict(box_trans,dataInt$PPvec)
      }
      
      for (comparison in whichCompareVec){
        dataIntCompare <- subset(dataInt,(blockVec %in% comparison))
        
        dataIntCompare <- dataIntCompare %>% 
          group_by(mapStimLevel) %>% 
          mutate(absDiff = PPvec - mean(PPvec[blockVec==comparison[1]]),
                 percentDiff = 100*(PPvec - mean(PPvec[blockVec==comparison[1]]))/mean(PPvec[blockVec==comparison[1]]) ) 
        
        dataIntCompare = as_data_frame(dataIntCompare)
        dataIntCompare$index = index
        
        
        name <- unique(dataIntCompare %>% filter(blockType!='baseline')%>%select(blockType))
        name <- as.character(name$blockType)
        
        dataIntCompare$overallBlockType <- name
        dataIntCompare <- dataIntCompare %>% mutate(pre_post = case_when(blockType == name ~ 'post',
                                                                         blockType=='baseline' ~'pre'
        ))
        dataList[[index]] = dataIntCompare
        blockList[[index]] = comparison
        
        fit.lm    = lm(PPvec ~ mapStimLevel + blockVec + mapStimLevel*blockVec,data=dataIntCompare)
        fit.lm    = lm(PPvec ~ mapStimLevel + blockVec,data=dataIntCompare)
        
        summary(fit.lm)
        # plot(fit.lm)
        summary(glht(fit.lm,linfct=mcp(blockVec="Tukey")))
        summary(glht(fit.lm,linfct=mcp(mapStimLevel="Tukey")))
        
        emmeans(fit.lm, list(pairwise ~ blockVec), adjust = "tukey")
        emmeans(fit.lm, list(pairwise ~ mapStimLevel), adjust = "tukey")
        
        emm_s.t <- emmeans(fit.lm, pairwise ~ blockVec | mapStimLevel)
        emm_s.t <- emmeans(fit.lm, pairwise ~ mapStimLevel | blockVec)
        
        anova(fit.lm)
        tab_model(fit.lm)
        
        index = index + 1
        
      }
      
      p <- ggplot(dataInt, aes(x=as.numeric(mapStimLevel), y=PPvec,color=stimLevelVec)) +
        geom_point(position=position_jitterdodge(dodge.width=0.250)) +  geom_smooth(method=lm) + facet_wrap(~blockVec, labeller = as_labeller(blockNames))+
        labs(x = expression(paste("Stimulation Current (mA)")),y=expression(paste("Peak to Peak Magnitude (",mu,"V)")),title = paste0("Subject ", subjectNum," DBS Paired Pulse EP Measurements")) +
        guides(colour=guide_colorbar("Stimulation Level"))
      print(p)
      
      if (savePlot && !avgMeas) {
        ggsave(paste0("subj_", subjectNum, "_ID_", sid,"_chan_",chanInt,"_compare_length_scatter_lm.png"), units="in", width=figWidth, height=figHeight, dpi=600)
        ggsave(paste0("subj_", subjectNum, "_ID_", sid,"_chan_",chanInt,"_compare_length_scatter_lm.eps"), units="in", width=figWidth, height=figHeight,device=cairo_ps, fallback_resolution=600)
        
      }
      else if (savePlot && avgMeas){
        ggsave(paste0("subj_", subjectNum, "_ID_", sid,"_chan_",chanInt,"_compare_length_scatter_lm_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
        ggsave(paste0("subj_", subjectNum, "_ID_", sid,"_chan_",chanInt,"_compare_length_scatter_lm_avg.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
        
      }
      
      dataToFit <- na.exclude(dataPP[dataPP$blockVec %in% blockIntLM & dataPP$chanVec==chanInt,])
      fit.glm    = glm(PPvec ~ blockVec + stimLevelVec,data=dataToFit)
      summary(fit.glm)
      summary(glht(fit.glm,linfct=mcp(blockVec="Tukey")))
      
    }
    
    
    # now do comparison at highest stim level relative to baseline
    dataList <- do.call(rbind,dataList)
    #blockList <- do.call(rbind,blockList)
    
    #plot
    grouped <- group_by(dataList, sidVec, chanVec, blockType,mapStimLevel)
    dataListSummarize <- summarise(grouped,meanPerc = mean(percentDiff),sdPerc = sd(percentDiff),
                                   meanAbs=mean(absDiff), sdDiff=sd(percentDiff),meanPP = mean(PPvec),sdPP = sd(PPvec))
    
    
    p3 <- ggplot(dataList, aes(x=as.numeric(mapStimLevel), y=percentDiff,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.75)) +
      labs(x = expression(paste("Stimulation level")),y=expression(paste("Percent Difference in EP Magnitude from Baseline")),
           title = paste0("Changes in EP magnitude"),color="Experimental Condition")
    print(p3)
    
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_percent.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_percent.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_percent_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_percent_avg.eps"), units="in", width=figWidth, height=figHeight,device=cairo_ps, fallback_resolution=600)
      
    }
    
    p4 <- ggplot(dataList, aes(x=as.numeric(mapStimLevel), y=absDiff,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.75)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Absolute Difference in EP Magnitude from Baseline (",mu,"V)")), color="Experimental Condition",title = paste0("Changes in EP magnitude"))
    print(p4)
    
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_abs.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_abs.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_abs_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_abs_avg.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    }
    
    p5 <- ggplot(dataListSummarize, aes(x=as.numeric(mapStimLevel), y=meanPerc,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.5)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Mean Percent Difference in EP Magnitude")), color="Experimental Condition",
           title = paste0("Changes in EP Magnitude"))
    print(p5)
    
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_mean_perc.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_perc.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_mean_perc_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_perc_avg.eps"), units="in", width=figWidth, height=figHeight,device=cairo_ps, fallback_resolution=600)
      
    }
    
    p6 <- ggplot(dataListSummarize, aes(x=as.numeric(mapStimLevel), y=meanAbs,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.5)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Mean Absolute Difference in EP Magnitude from Baseline (",mu,"V)")),
           color="Experimental Condition",title = paste0("Changes in EP Magnitude"))
    print(p6)
    
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_mean_abs.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_abs.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_mean_abs_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_abs_avg.eps"), units="in", width=figWidth, height=figHeight, device=cairo_ps, fallback_resolution=600)
      
    }
    
    p7 <- ggplot(dataList, aes(x=as.numeric(mapStimLevel), y=PPvec,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.75)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Peak to Peak voltage (",mu,"V)")),
           color="Experimental Condition",title = paste0("EP Magnitude by Length of Conditioning"))
    print(p7)
    # if (savePlot && !avgMeas) {
    #   ggsave(paste0("across_a23ed_PP.png"), units="in", width=figWidth, height=figHeight, dpi=600)
    #   ggsave(paste0("across_a23ed_PP.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
    #   
    # } else if (savePlot && avgMeas){
    #   ggsave(paste0("across_a23ed_PP_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
    #   ggsave(paste0("across_a23ed_PP_avg.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
    #   
    #   
    # }
    # 
    # 
    
    
    p7 <- ggplot(dataList, aes(x=as.numeric(mapStimLevel), y=PPvec,color=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.75)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Peak to Peak voltage (",mu,"V)")),
           color="Experimental Condition",title = paste0("EP Magnitude by Length of Conditioning")) + scale_color_manual(values=c("#F8766D","#bedd73","#7CAE00" ))
    
    print(p7)
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_PP.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_PP.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_PP_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_PP_avg.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
      
    }
    
    
    p8 <- ggplot(dataListSummarize, aes(x=as.numeric(mapStimLevel), y=meanPP,colour=blockType,fill=blockType)) +
      geom_point(position=position_jitterdodge(dodge.width=0.5)) +geom_smooth(method=lm) +
      labs(x = expression(paste("Stimulation Level")),y=expression(paste("Mean Peak to Peak Voltage (",mu,"V)")), color="Experimental Condition",
           title = paste0("EP Magnitude by Length of Conditioning"))
    print(p8)
    
    if (savePlot && !avgMeas) {
      ggsave(paste0("across_a23ed_mean_PP.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_PP.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
      
    } else if (savePlot && avgMeas){
      ggsave(paste0("across_a23ed_mean_PP_avg.png"), units="in", width=figWidth, height=figHeight, dpi=600)
      ggsave(paste0("across_a23ed_mean_PP_avg.eps"), units="in", width=figWidth, height=figHeight, dpi=600,device=cairo_ps, fallback_resolution=600)
      
    }  
    
    if (repeatedMeasures){
      fit.lmmPP = lm(PPvec ~ mapStimLevel + overallBlockType*pre_post,data=dataList)
      emmeans(fit.lmmPP, list(pairwise ~ overallBlockType), adjust = "tukey")
      
      emm_s.t <- emmeans(fit.lmmPP, pairwise ~ overallBlockType | mapStimLevel)
      
      emm_s.t <- emmeans(fit.lmmPP, pairwise ~ mapStimLevel | overallBlockType)
    }
    else{}

    fit.lmmPP = lm(PPvec ~ mapStimLevel + blockType,data=dataList)
    emmeans(fit.lmmPP, list(pairwise ~ blockType), adjust = "tukey")
    
    emm_s.t <- emmeans(fit.lmmPP, pairwise ~ blockType | mapStimLevel)
    
    emm_s.t <- emmeans(fit.lmmPP, pairwise ~ mapStimLevel | blockType)
    
    }
    summary(fit.lmmPP)
    # plot(fit.lm)
    summary(glht(fit.lmmPP,linfct=mcp(blockType="Tukey")))
    summary(glht(fit.lmmPP,linfct=mcp(overallBlockType="Tukey")))
    
    
    summary(glht(fit.lmmPP,linfct=mcp(mapStimLevel="Tukey")))
    
    
    emmeans(fit.lmmPP, list(pairwise ~ mapStimLevel), adjust = "tukey")
  
    
    anova(fit.lmmPP)
    tab_model(fit.lmmPP)
    
    fit.lmmdiff = lm(absDiff ~ mapStimLevel + blockType,data=dataList)
    
    fit.lm = lm(absDiff ~ mapStimLevel + blockType + chanInCond ,data=dataList)
    fit.lm = lm(absDiff ~ mapStimLevel + blockType ,data=dataList)
    tab_model(fit.lm)
    
    summary(fit.lmmdiff)
    # plot(fit.lm)
    plot(fit.lmmPP)
    qqnorm(resid(fit.lmmPP))
    qqline(resid(fit.lmmPP))
    summary(glht(fit.lmmdiff,linfct=mcp(blockType="Tukey")))
    summary(glht(fit.lmmdiff,linfct=mcp(mapStimLevel="Tukey")))
    
    emmeans(fit.lmmdiff, list(pairwise ~ blockType), adjust = "tukey")
    emmeans(fit.lmmdiff, list(pairwise ~ mapStimLevel), adjust = "tukey")
    
    emm_s.t <- emmeans(fit.lmmdiff, pairwise ~ blockType | mapStimLevel)
    emm_s.t <- emmeans(fit.lmmdiff, pairwise ~ mapStimLevel | blockType)
    
    anova(fit.lmmdiff)
    tab_model(fit.lmmdiff)
    
  }
}

  