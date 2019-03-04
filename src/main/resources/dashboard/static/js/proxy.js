(function (L) {
    var _this = null;
    L.Proxy = L.Proxy || {};
    _this = L.Proxy = {
        data: {
        },

        init: function () {
            L.Common.loadConfigs("proxy", _this, true);
            _this.initEvents();
        },

        initEvents: function () {
            L.Common.initRuleAddDialog("proxy", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("proxy", _this);//删除规则对话框
            L.Common.initRuleEditDialog("proxy", _this);//编辑规则对话框
            L.Common.initRuleSortEvent("proxy", _this);

            L.Common.initSelectorAddDialog("proxy", _this);
            L.Common.initSelectorDeleteDialog("proxy", _this);
            L.Common.initSelectorEditDialog("proxy", _this);
            L.Common.initSelectorSortEvent("proxy", _this);
            L.Common.initSelectorClickEvent("proxy", _this);

            L.Common.initSelectorTypeChangeEvent();//选择器类型选择事件
            L.Common.initConditionAddOrRemove();//添加或删除条件
            L.Common.initJudgeTypeChangeEvent();//judge类型选择事件
            L.Common.initConditionTypeChangeEvent();//condition类型选择事件

            L.Common.initExtractionAddOrRemove();//添加或删除条件
            L.Common.initExtractionTypeChangeEvent();//extraction类型选择事件
            L.Common.initExtractionAddBtnEvent();//添加提前项按钮事件
            L.Common.initExtractionHasDefaultValueOrNotEvent();//提取项是否有默认值选择事件

            L.Common.initViewAndDownloadEvent("proxy", _this);
            L.Common.initSwitchBtn("proxy", _this);//proxy关闭、开启
            L.Common.initSyncDialog("proxy", _this);//编辑规则对话框
        },

        buildRule: function () {
            var result = {
                success: false,
                data: {
                    name: null,
                    judge: {},
                    extractor: {},
                    handle: {}
                }
            };

            //build name and judge
            var buildJudgeResult = L.Common.buildJudge();
            if (buildJudgeResult.success == true) {
                result.data.name = buildJudgeResult.data.name;
                result.data.judge = buildJudgeResult.data.judge;
            } else {
                result.success = false;
                result.data = buildJudgeResult.data;
                return result;
            }

            //build extractor
            var buildExtractorResult = L.Common.buildExtractor();
            if (buildExtractorResult.success == true) {
                result.data.extractor = buildExtractorResult.data.extractor;
            } else {
                result.success = false;
                result.data = buildExtractorResult.data;
                return result;
            }

            //build handle
            var buildHandleResult = _this.buildHandle();
            if (buildHandleResult.success == true) {
                result.data.handle = buildHandleResult.handle;
            } else {
                result.success = false;
                result.data = buildHandleResult.data;
                return result;
            }

            //enable or not
            var enable = $('#rule-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
        },

        buildHandle: function () {
            var result = {};
            var handle = {};
            var url_tmpl = $("#rule-handle-url-template").val();
            if (!url_tmpl) {
                result.success = false;
                result.data = "要跳转到的url template不得为空";
                return result;
            }
            handle.url_tmpl = url_tmpl;
            handle.trim_qs = ($("#rule-handle-trim-qs").val() === "true");
            handle.proxy_status = $("#rule-handle-proxy-status").val() == "301"?"301":"302";
            handle.log = ($("#rule-handle-log").val() === "true");
            result.success = true;
            result.handle = handle;
            return result;
        },
    };
}(APP));
